import Cocoa
import Darwin
import WebKit

struct ServiceConfig: Codable {
    let id: String
    let name: String
    let workDir: String
    let command: String
    let executable: String?
    let arguments: [String]?
    let environment: [String: String]?
    let processSignature: String
    let healthURL: String
    let healthContains: String?
    let startupTimeout: Double
}

struct ExternalConfig: Codable {
    let id: String
    let executable: String
    let arguments: [String]
    let workDir: String
    let processSignature: String
}

struct SystemConfig: Codable {
    let id: String
    let name: String
    let subtitle: String
    let displayURL: String?
    let width: Double
    let height: Double
    let services: [ServiceConfig]
    let external: ExternalConfig?
    let stopServiceIDs: [String]?
    let ephemeralWebData: Bool?
}

struct PIDRecord: Codable {
    let id: String
    let pid: Int32
    let signature: String
    let startedAt: String
}

final class SystemShellDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, NSWindowDelegate {
    private var config: SystemConfig!
    private var window: NSWindow!
    private var contentRoot: NSView!
    private var statusLabel: NSTextField!
    private var detailLabel: NSTextField!
    private var progress: NSProgressIndicator!
    private var retryButton: NSButton!
    private var logsButton: NSButton!
    private var exitOnlyButton: NSButton!
    private var webView: WKWebView?
    private var ownedProcesses: [Process] = []
    private var lastLogURL: URL?
    private var stopButton: NSButton!
    private var allowWindowClose = false
    private var stopInProgress = false
    private var externalMonitor: Timer?
    private var serviceMonitor: Timer?
    private var serviceMonitorBusy = false
    private var serviceFailureCounts: [String: Int] = [:]
    private var lastProbeErrorCodes: [String: Int] = [:]
    private var recoveringServiceIDs: Set<String> = []
    private var mobileWindowFrame: NSRect?
    private var webPresentationActive = false
    private var startupGeneration = 0
    private var terminationReplyPending = false
    private let processQueue = DispatchQueue(label: "PortDemo.SystemShell.ProcessLifecycle", qos: .userInitiated)

    private lazy var runtimeRoot: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("港航演示中心/Runtime", isDirectory: true)
    }()

    private lazy var processRuntime = ManagedProcessRuntime(runtimeRoot: runtimeRoot)

    private func managedService(_ service: ServiceConfig) -> ManagedService {
        ManagedService(id: service.id, workDir: expandedPath(service.workDir),
                       processSignature: service.processSignature, healthURL: service.healthURL)
    }

    private var configuredProcesses: [ManagedService] {
        guard let config else { return [] }
        if let external = config.external {
            return [ManagedService(id: external.id, workDir: expandedPath(external.workDir),
                                   processSignature: external.processSignature, healthURL: nil)]
        }
        return config.services.map(managedService)
    }

    private func expandedPath(_ value: String) -> String {
        (value as NSString).expandingTildeInPath
    }

    private func expandedArgument(_ value: String) -> String {
        value
            .replacingOccurrences(of: "$HOME", with: NSHomeDirectory())
            .replacingOccurrences(of: "${HOME}", with: NSHomeDirectory())
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        do {
            config = try loadConfig()
            try prepareRuntimeDirectories()
            guard processRuntime.acquireLease(ownerID: config.id, serviceIDs: configuredProcesses.map(\.id)) else {
                throw NSError(domain: "DemoShell", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "无法登记服务使用记录，请检查启动日志目录权限。"])
            }
            buildWindow()
            NSApp.activate(ignoringOtherApps: true)
            if let external = config.external {
                launchExternal(external)
            } else {
                startServices()
            }
        } catch {
            showFatalError("应用配置无法读取", detail: error.localizedDescription)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard config != nil, !allowWindowClose else { return .terminateNow }
        terminationReplyPending = true
        if !stopInProgress { beginStopAndExit() }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        externalMonitor?.invalidate()
        serviceMonitor?.invalidate()
        if let config { processRuntime.releaseLease(ownerID: config.id) }
    }

    private func loadConfig() throws -> SystemConfig {
        guard let url = Bundle.main.url(forResource: "system", withExtension: "json") else {
            throw NSError(domain: "DemoShell", code: 1, userInfo: [NSLocalizedDescriptionKey: "缺少 system.json"])
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(SystemConfig.self, from: data)
    }

    private func prepareRuntimeDirectories() throws {
        try FileManager.default.createDirectory(
            at: runtimeRoot.appendingPathComponent("pids", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: runtimeRoot.appendingPathComponent("logs", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    private func buildWindow() {
        let frame = NSRect(x: 0, y: 0, width: config.width, height: config.height)
        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = config.name
        window.delegate = self
        window.minSize = NSSize(width: min(config.width, 430), height: min(config.height, 560))
        window.center()
        if config.id == "mobile" { mobileWindowFrame = window.frame }

        stopButton = NSButton(title: "■  停止并退出系统", target: self, action: #selector(confirmStopAndExit))
        stopButton.bezelStyle = .rounded
        stopButton.contentTintColor = .systemRed
        stopButton.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        stopButton.toolTip = "核验进程身份后停止真实后台服务，并关闭当前窗口"
        stopButton.frame = NSRect(x: 0, y: 0, width: 138, height: 28)
        let stopAccessory = NSTitlebarAccessoryViewController()
        stopAccessory.view = stopButton
        stopAccessory.layoutAttribute = .right
        window.addTitlebarAccessoryViewController(stopAccessory)

        contentRoot = NSView(frame: frame)
        contentRoot.wantsLayer = true
        contentRoot.layer?.backgroundColor = NSColor(calibratedRed: 0.035, green: 0.065, blue: 0.115, alpha: 1).cgColor
        window.contentView = contentRoot

        let badge = NSTextField(labelWithString: "LOCAL  ·  VERIFIED LINKAGE")
        badge.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        badge.textColor = NSColor(calibratedRed: 0.30, green: 0.78, blue: 1.0, alpha: 1)
        badge.alignment = .center
        badge.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: config.name)
        title.font = NSFont.systemFont(ofSize: 30, weight: .bold)
        title.textColor = .white
        title.alignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = NSTextField(wrappingLabelWithString: config.subtitle)
        subtitle.font = NSFont.systemFont(ofSize: 14, weight: .regular)
        subtitle.textColor = NSColor(calibratedWhite: 0.72, alpha: 1)
        subtitle.alignment = .center
        subtitle.maximumNumberOfLines = 2
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        progress = NSProgressIndicator()
        progress.style = .spinning
        progress.controlSize = .large
        progress.startAnimation(nil)
        progress.translatesAutoresizingMaskIntoConstraints = false

        statusLabel = NSTextField(labelWithString: "正在准备独立系统…")
        statusLabel.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        statusLabel.textColor = .white
        statusLabel.alignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        detailLabel = NSTextField(wrappingLabelWithString: "正在核验本地服务身份与端口状态")
        detailLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        detailLabel.textColor = NSColor(calibratedWhite: 0.60, alpha: 1)
        detailLabel.alignment = .center
        detailLabel.maximumNumberOfLines = 3
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        retryButton = NSButton(title: "重新尝试", target: self, action: #selector(retryStartup))
        retryButton.bezelStyle = .rounded
        retryButton.isHidden = true
        retryButton.translatesAutoresizingMaskIntoConstraints = false

        logsButton = NSButton(title: "查看启动日志", target: self, action: #selector(openLogs))
        logsButton.bezelStyle = .rounded
        logsButton.isHidden = true
        logsButton.translatesAutoresizingMaskIntoConstraints = false

        exitOnlyButton = NSButton(title: "仅退出界面", target: self, action: #selector(exitShellOnly))
        exitOnlyButton.bezelStyle = .rounded
        exitOnlyButton.toolTip = "关闭当前窗口，但保留无法安全确认身份的后台进程"
        exitOnlyButton.isHidden = true
        exitOnlyButton.translatesAutoresizingMaskIntoConstraints = false

        [badge, title, subtitle, progress, statusLabel, detailLabel, retryButton, logsButton, exitOnlyButton].forEach(contentRoot.addSubview)

        NSLayoutConstraint.activate([
            badge.centerXAnchor.constraint(equalTo: contentRoot.centerXAnchor),
            badge.centerYAnchor.constraint(equalTo: contentRoot.centerYAnchor, constant: -126),
            title.centerXAnchor.constraint(equalTo: contentRoot.centerXAnchor),
            title.topAnchor.constraint(equalTo: badge.bottomAnchor, constant: 18),
            subtitle.centerXAnchor.constraint(equalTo: contentRoot.centerXAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),
            subtitle.widthAnchor.constraint(lessThanOrEqualTo: contentRoot.widthAnchor, multiplier: 0.72),
            progress.centerXAnchor.constraint(equalTo: contentRoot.centerXAnchor),
            progress.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 34),
            statusLabel.centerXAnchor.constraint(equalTo: contentRoot.centerXAnchor),
            statusLabel.topAnchor.constraint(equalTo: progress.bottomAnchor, constant: 20),
            detailLabel.centerXAnchor.constraint(equalTo: contentRoot.centerXAnchor),
            detailLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            detailLabel.widthAnchor.constraint(lessThanOrEqualTo: contentRoot.widthAnchor, multiplier: 0.74),
            retryButton.centerXAnchor.constraint(equalTo: contentRoot.centerXAnchor, constant: -70),
            retryButton.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 24),
            retryButton.widthAnchor.constraint(equalToConstant: 120),
            logsButton.centerXAnchor.constraint(equalTo: contentRoot.centerXAnchor, constant: 70),
            logsButton.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 24),
            logsButton.widthAnchor.constraint(equalToConstant: 120),
            exitOnlyButton.centerXAnchor.constraint(equalTo: contentRoot.centerXAnchor),
            exitOnlyButton.topAnchor.constraint(equalTo: retryButton.bottomAnchor, constant: 10),
            exitOnlyButton.widthAnchor.constraint(equalToConstant: 120)
        ])

        window.makeKeyAndOrderFront(nil)
    }

    private func startServices() {
        guard !stopInProgress else { return }
        startupGeneration += 1
        serviceMonitor?.invalidate()
        serviceMonitor = nil
        serviceMonitorBusy = false
        serviceFailureCounts.removeAll()
        lastProbeErrorCodes.removeAll()
        recoveringServiceIDs.removeAll()
        webView?.removeFromSuperview()
        webView = nil
        retryButton.isHidden = true
        logsButton.isHidden = true
        exitOnlyButton.isHidden = true
        progress.isHidden = false
        progress.startAnimation(nil)
        ensureService(at: 0)
    }

    private func ensureService(at index: Int) {
        guard !stopInProgress else { return }
        let generation = startupGeneration
        guard index < config.services.count else {
            showSystemUI()
            return
        }
        let service = config.services[index]
        statusLabel.stringValue = "正在连接 \(service.name)"
        detailLabel.stringValue = "检查真实服务与端口契约…"

        probe(service) { [weak self] healthy in
            guard let self, !self.stopInProgress, generation == self.startupGeneration else { return }
            if healthy {
                guard self.processRuntime.adopt(self.managedService(service)) else {
                    self.showStartupFailure(service, detail: "服务已响应，但无法核验或登记后台进程，请查看启动日志。")
                    return
                }
                self.ensureService(at: index + 1)
                return
            }

            if self.hasLiveRecordedProcess(id: service.id) {
                self.detailLabel.stringValue = "服务已在启动，等待就绪回执…"
                self.poll(service, deadline: Date().addingTimeInterval(service.startupTimeout)) { ok in
                    if ok { self.ensureService(at: index + 1) }
                    else { self.showStartupFailure(service) }
                }
                return
            }

            do {
                try self.launch(service)
                self.detailLabel.stringValue = "后台进程已启动，等待健康检查通过…"
                self.poll(service, deadline: Date().addingTimeInterval(service.startupTimeout)) { ok in
                    if ok { self.ensureService(at: index + 1) }
                    else { self.showStartupFailure(service) }
                }
            } catch {
                self.showStartupFailure(service, detail: error.localizedDescription)
            }
        }
    }

    private func probe(_ service: ServiceConfig, completion: @escaping (Bool) -> Void) {
        let generation = startupGeneration
        guard let url = URL(string: service.healthURL) else {
            completion(false)
            return
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 2.0)
        request.setValue("PortDemoDesktop/1.0", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let http = response as? HTTPURLResponse
            let statusOK = http.map { (200..<300).contains($0.statusCode) } ?? false
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let identityOK = service.healthContains.map { body.contains($0) } ?? true
            DispatchQueue.main.async {
                guard let self, !self.stopInProgress, generation == self.startupGeneration else { return }
                self.lastProbeErrorCodes[service.id] = (error as NSError?)?.code
                completion(statusOK && identityOK)
            }
        }.resume()
    }

    private func poll(_ service: ServiceConfig, deadline: Date, completion: @escaping (Bool) -> Void) {
        guard !stopInProgress else { return }
        let generation = startupGeneration
        probe(service) { [weak self] healthy in
            guard let self, !self.stopInProgress, generation == self.startupGeneration else { return }
            if healthy {
                completion(self.processRuntime.adopt(self.managedService(service)))
            } else if Date() >= deadline {
                completion(false)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                    guard !self.stopInProgress, generation == self.startupGeneration else { return }
                    self.poll(service, deadline: deadline, completion: completion)
                }
            }
        }
    }

    private func startServiceMonitoring() {
        guard !stopInProgress, config.external == nil, !config.services.isEmpty else { return }
        serviceMonitor?.invalidate()
        serviceFailureCounts.removeAll()
        serviceMonitor = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            self?.monitorConfiguredServices()
        }
    }

    private func monitorConfiguredServices() {
        guard !stopInProgress, !serviceMonitorBusy else { return }
        serviceMonitorBusy = true
        monitorService(at: 0) { [weak self] in
            self?.serviceMonitorBusy = false
        }
    }

    private func monitorService(at index: Int, completion: @escaping () -> Void) {
        guard !stopInProgress, index < config.services.count else {
            completion()
            return
        }
        let service = config.services[index]
        let generation = startupGeneration
        probe(service) { [weak self] healthy in
            guard let self, !self.stopInProgress, generation == self.startupGeneration else { return }
            if healthy {
                self.serviceFailureCounts[service.id] = 0
                self.monitorService(at: index + 1, completion: completion)
                return
            }

            let failures = (self.serviceFailureCounts[service.id] ?? 0) + 1
            self.serviceFailureCounts[service.id] = failures
            guard failures >= 3 else {
                self.monitorService(at: index + 1, completion: completion)
                return
            }

            self.recoverStoppedService(service) {
                self.monitorService(at: index + 1, completion: completion)
            }
        }
    }

    private func recoverStoppedService(_ service: ServiceConfig, completion: @escaping () -> Void) {
        guard !stopInProgress, !recoveringServiceIDs.contains(service.id) else {
            completion()
            return
        }

        recoveringServiceIDs.insert(service.id)
        let generation = startupGeneration
        let launchAndPoll = { [weak self] in
            guard let self, !self.stopInProgress, generation == self.startupGeneration else { return }
            do {
                try self.launch(service)
            } catch {
                self.recoveringServiceIDs.remove(service.id)
                completion()
                return
            }

            self.poll(service, deadline: Date().addingTimeInterval(service.startupTimeout)) { [weak self] recovered in
                guard let self else { return }
                self.recoveringServiceIDs.remove(service.id)
                if recovered {
                    self.serviceFailureCounts[service.id] = 0
                    if let view = self.webView {
                        // Do not supersede a user-initiated route change. WebKit
                        // reports the displaced request as NSURLErrorCancelled
                        // (-999); the active navigation will read the recovered
                        // service on its own.
                        if !view.isLoading {
                            view.reloadFromOrigin()
                        }
                    } else {
                        self.statusLabel.textColor = .white
                        self.showSystemUI()
                    }
                }
                completion()
            }
        }

        guard hasLiveRecordedProcess(id: service.id) else {
            launchAndPoll()
            return
        }

        // A timeout can be a long-running backend request, so it must not kill
        // a managed process. A repeated -1004 means the port actively refused
        // the connection: the signed PID is no longer serving and can be
        // replaced after an exact identity check.
        guard lastProbeErrorCodes[service.id] == NSURLErrorCannotConnectToHost else {
            recoveringServiceIDs.remove(service.id)
            completion()
            return
        }
        let managed = managedService(service)
        let ownerID = config.id
        processQueue.async { [weak self] in
            guard let self else { return }
            let canRecover = DispatchQueue.main.sync {
                !self.stopInProgress && generation == self.startupGeneration
            }
            guard canRecover else { return }
            let protected = self.processRuntime.leasedServiceIDs(excludingOwnerID: ownerID)
            let result = self.processRuntime.stop([managed], protectedServiceIDs: protected)
            DispatchQueue.main.async {
                guard !self.stopInProgress, generation == self.startupGeneration else { return }
                if result.remaining == 0 && result.protectedServiceIDs.isEmpty { launchAndPoll() }
                else {
                    self.recoveringServiceIDs.remove(service.id)
                    completion()
                }
            }
        }
    }

    private func launch(_ service: ServiceConfig) throws {
        guard !stopInProgress else {
            throw NSError(domain: "DemoShell", code: NSUserCancelledError)
        }
        let logURL = runtimeRoot.appendingPathComponent("logs/\(service.id).log")
        lastLogURL = logURL
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        let logHandle = try FileHandle(forWritingTo: logURL)
        try logHandle.seekToEnd()

        let process = Process()
        let workDirectory = URL(fileURLWithPath: expandedPath(service.workDir), isDirectory: true)
        process.currentDirectoryURL = workDirectory
        if let configuredExecutable = service.executable, !configuredExecutable.isEmpty {
            let expandedExecutable = expandedArgument(configuredExecutable)
            process.executableURL = expandedExecutable.hasPrefix("/")
                ? URL(fileURLWithPath: expandedExecutable)
                : workDirectory.appendingPathComponent(expandedExecutable)
            process.arguments = (service.arguments ?? []).map(expandedArgument)
            var environment = ProcessInfo.processInfo.environment
            service.environment?.forEach { key, value in environment[key] = expandedArgument(value) }
            process.environment = environment
        } else {
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            // Legacy configurations still use a shell command. New services
            // should use executable/arguments/environment so no shell startup
            // or quoting step can stall before the real process is launched.
            process.arguments = ["-c", "exec \(service.command)"]
        }
        process.standardOutput = logHandle
        process.standardError = logHandle
        try process.run()
        ownedProcesses.append(process)
        writePID(id: service.id, pid: process.processIdentifier, signature: service.processSignature)
    }

    private func launchExternal(_ external: ExternalConfig) {
        guard !stopInProgress else { return }
        statusLabel.stringValue = "正在启动 \(config.name)"
        detailLabel.stringValue = "加载 Godot 主场景与真实项目资源…"

        if let record = readPID(id: external.id), isRecordAlive(record) {
            NSRunningApplication(processIdentifier: record.pid)?.activate(options: [.activateAllWindows])
            statusLabel.stringValue = "系统已经运行"
            detailLabel.stringValue = "已切换到现有独立窗口；关闭本控制窗会停止真实进程"
            progress.stopAnimation(nil)
            monitorExternalProcess(id: external.id)
            return
        }

        do {
            let logURL = runtimeRoot.appendingPathComponent("logs/\(external.id).log")
            lastLogURL = logURL
            if !FileManager.default.fileExists(atPath: logURL.path) {
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: logURL)
            try handle.seekToEnd()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: expandedPath(external.executable))
            process.arguments = external.arguments.map(expandedArgument)
            process.currentDirectoryURL = URL(fileURLWithPath: expandedPath(external.workDir), isDirectory: true)
            process.standardOutput = handle
            process.standardError = handle
            try process.run()
            ownedProcesses.append(process)
            writePID(id: external.id, pid: process.processIdentifier, signature: external.processSignature)
            statusLabel.stringValue = "独立窗口已启动"
            detailLabel.stringValue = "航行模拟器正在载入；关闭本控制窗会停止真实进程"
            progress.stopAnimation(nil)
            monitorExternalProcess(id: external.id)
        } catch {
            showStartupFailure(nil, detail: error.localizedDescription)
        }
    }

    private func showSystemUI() {
        guard !stopInProgress else { return }
        guard let rawURL = config.displayURL, let url = URL(string: rawURL) else {
            showFatalError("显示地址无效", detail: config.displayURL ?? "未配置")
            return
        }

        progress.stopAnimation(nil)
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        let webConfig = WKWebViewConfiguration()
        webConfig.defaultWebpagePreferences = preferences
        webConfig.websiteDataStore = config.ephemeralWebData == true ? .nonPersistent() : .default()

        let view = WKWebView(frame: contentRoot.bounds, configuration: webConfig)
        view.autoresizingMask = [.width, .height]
        view.navigationDelegate = self
        view.allowsMagnification = true
        contentRoot.addSubview(view)
        webView = view
        view.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15))
        startServiceMonitoring()
        window.title = config.name
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleWebLoadError(webView, error: error)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        applyPresentationMode(for: webView.url)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleWebLoadError(webView, error: error)
    }

    private func applyPresentationMode(for url: URL?) {
        guard config.id == "mobile", let url else { return }
        let isDesktopWeb = url.port == 8000
        guard isDesktopWeb != webPresentationActive else { return }

        if isDesktopWeb {
            mobileWindowFrame = window.frame
            let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? window.frame
            let width = min(1450, max(980, visible.width - 36))
            let height = min(900, max(680, visible.height - 36))
            let target = NSRect(
                x: visible.midX - width / 2,
                y: visible.midY - height / 2,
                width: width,
                height: height
            )
            window.minSize = NSSize(width: min(980, width), height: min(680, height))
            window.title = "PortAI × Web RL 审批"
            applyStableWebFrame(target)
        } else {
            let fallback = NSRect(x: window.frame.midX - config.width / 2,
                                  y: window.frame.midY - config.height / 2,
                                  width: config.width, height: config.height)
            window.minSize = NSSize(width: min(config.width, 430), height: min(config.height, 560))
            window.title = config.name
            applyStableWebFrame(mobileWindowFrame ?? fallback)
        }
        webPresentationActive = isDesktopWeb
    }

    private func applyStableWebFrame(_ frame: NSRect) {
        // Animated NSWindow resizing can expose partially repainted CanvasKit
        // tiles in WKWebView. Switch dimensions atomically, then force the web
        // surface to observe its final bounds before the next frame is drawn.
        window.setFrame(frame, display: true, animate: false)
        contentRoot.layoutSubtreeIfNeeded()
        guard let webView else { return }
        webView.frame = contentRoot.bounds
        webView.needsDisplay = true
        webView.layer?.setNeedsDisplay()
        webView.evaluateJavaScript(
            "window.dispatchEvent(new Event('resize')); requestAnimationFrame(() => window.dispatchEvent(new Event('resize')));",
            completionHandler: nil
        )
    }

    private func handleWebLoadError(_ failedWebView: WKWebView, error: Error) {
        guard failedWebView === webView else { return }
        let nsError = error as NSError
        // WebKit uses -999 when a request is intentionally replaced by a new
        // navigation (for example V3 -> homepage). It is not a page failure.
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return
        }
        failedWebView.removeFromSuperview()
        webView = nil
        showFatalError("界面加载失败", detail: error.localizedDescription)
    }

    private func showStartupFailure(_ service: ServiceConfig?, detail: String? = nil) {
        let serviceName = service?.name ?? config.name
        showFatalError("\(serviceName) 未能就绪", detail: detail ?? "请查看启动日志；若端口被其他应用占用，本启动器会拒绝连接错误服务。")
    }

    private func showFatalError(_ title: String, detail: String) {
        if window == nil {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = detail
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        progress.stopAnimation(nil)
        progress.isHidden = true
        statusLabel.stringValue = title
        statusLabel.textColor = NSColor(calibratedRed: 1.0, green: 0.42, blue: 0.42, alpha: 1)
        detailLabel.stringValue = detail
        retryButton.isHidden = false
        logsButton.isHidden = lastLogURL == nil
        exitOnlyButton.isHidden = false
    }

    @objc private func retryStartup() {
        statusLabel.textColor = .white
        exitOnlyButton.isHidden = true
        if let external = config.external { launchExternal(external) }
        else { startServices() }
    }

    @objc private func exitShellOnly() {
        startupGeneration += 1
        serviceMonitor?.invalidate()
        serviceMonitor = nil
        externalMonitor?.invalidate()
        externalMonitor = nil
        processRuntime.releaseLease(ownerID: config.id)
        allowWindowClose = true
        if terminationReplyPending {
            terminationReplyPending = false
            NSApp.reply(toApplicationShouldTerminate: true)
        } else {
            NSApp.terminate(nil)
        }
    }

    @objc private func openLogs() {
        guard let url = lastLogURL else { return }
        NSWorkspace.shared.open(url)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if allowWindowClose { return true }
        confirmStopAndExit()
        return false
    }

    @objc private func confirmStopAndExit() {
        guard !stopInProgress else { return }
        let alert = NSAlert()
        alert.messageText = "停止并退出 \(config.name)？"
        alert.informativeText = "关闭当前界面，并停止不再被其他已打开系统使用的后台服务。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "停止并退出")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        beginStopAndExit()
    }

    private func beginStopAndExit() {
        guard !stopInProgress else { return }
        stopInProgress = true
        startupGeneration += 1
        serviceMonitor?.invalidate()
        serviceMonitor = nil
        externalMonitor?.invalidate()
        externalMonitor = nil
        processRuntime.releaseLease(ownerID: config.id)
        stopButton?.isEnabled = false
        stopButton?.title = "正在停止…"
        webView?.isHidden = true
        progress?.isHidden = false
        progress?.startAnimation(nil)
        statusLabel?.stringValue = "正在停止后台服务"
        statusLabel?.textColor = .white
        detailLabel?.stringValue = "正在核验进程与端口是否释放…"

        let services = configuredProcesses
        processQueue.async { [weak self] in
            guard let self else { return }
            let protected = self.processRuntime.leasedServiceIDs()
            let result = self.processRuntime.stop(services, protectedServiceIDs: protected)
            DispatchQueue.main.async {
                self.progress?.stopAnimation(nil)
                self.statusLabel?.stringValue = result.remaining == 0 ? "当前系统已退出" : "仍有后台服务未退出"
                if result.remaining == 0 {
                    self.detailLabel?.stringValue = result.protectedServiceIDs.isEmpty
                        ? "后台进程已退出，端口已释放。"
                        : "当前界面已退出；其他已打开系统仍在使用的共享后台已保留。"
                    self.allowWindowClose = true
                    if self.terminationReplyPending {
                        self.terminationReplyPending = false
                        NSApp.reply(toApplicationShouldTerminate: true)
                    } else {
                        NSApp.terminate(nil)
                    }
                } else {
                    self.detailLabel?.stringValue = "仍有 \(result.remaining) 项未停止。\(result.errors.joined(separator: "；")) 可再次核验停止，或仅退出界面并保留该进程。"
                    self.stopInProgress = false
                    self.serviceMonitorBusy = false
                    self.recoveringServiceIDs.removeAll()
                    self.serviceFailureCounts.removeAll()
                    self.lastProbeErrorCodes.removeAll()
                    _ = self.processRuntime.acquireLease(ownerID: self.config.id, serviceIDs: services.map(\.id))
                    self.stopButton?.isEnabled = true
                    self.stopButton?.title = "■  再次停止并退出"
                    self.retryButton?.isHidden = false
                    self.logsButton?.isHidden = self.lastLogURL == nil
                    self.exitOnlyButton?.isHidden = false
                    if self.terminationReplyPending {
                        self.terminationReplyPending = false
                        NSApp.reply(toApplicationShouldTerminate: false)
                    }
                }
            }
        }
    }

    private func monitorExternalProcess(id: String) {
        externalMonitor?.invalidate()
        externalMonitor = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self else { return }
            guard let record = self.readPID(id: id), self.isRecordAlive(record) else {
                timer.invalidate()
                try? FileManager.default.removeItem(at: self.pidURL(id: id))
                self.allowWindowClose = true
                NSApp.terminate(nil)
                return
            }
        }
    }

    private func pidURL(id: String) -> URL {
        runtimeRoot.appendingPathComponent("pids/\(id).json")
    }

    private func writePID(id: String, pid: Int32, signature: String) {
        let formatter = ISO8601DateFormatter()
        let record = PIDRecord(id: id, pid: pid, signature: signature, startedAt: formatter.string(from: Date()))
        if let data = try? JSONEncoder().encode(record) {
            try? data.write(to: pidURL(id: id), options: .atomic)
        }
    }

    private func readPID(id: String) -> PIDRecord? {
        guard let data = try? Data(contentsOf: pidURL(id: id)) else { return nil }
        return try? JSONDecoder().decode(PIDRecord.self, from: data)
    }

    private func hasLiveRecordedProcess(id: String) -> Bool {
        if let service = config.services.first(where: { $0.id == id }) {
            return processRuntime.isRunning(managedService(service))
        }
        guard let record = readPID(id: id), isRecordAlive(record) else {
            try? FileManager.default.removeItem(at: pidURL(id: id))
            return false
        }
        return true
    }

    private func isRecordAlive(_ record: PIDRecord) -> Bool {
        guard record.pid > 1, Darwin.kill(record.pid, 0) == 0 else { return false }
        return processCommand(pid: record.pid).contains(record.signature)
    }

    private func processCommand(pid: Int32) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", String(pid), "-o", "command="]
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}

@main
struct SystemShellApplication {
    static func main() {
        let application = NSApplication.shared
        let applicationDelegate = SystemShellDelegate()
        application.delegate = applicationDelegate
        withExtendedLifetime(applicationDelegate) { application.run() }
    }
}
