import Cocoa
import Darwin
import WebKit

struct ServiceConfig: Codable {
    let id: String
    let name: String
    let workDir: String
    let command: String
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
    private var webView: WKWebView?
    private var ownedProcesses: [Process] = []
    private var lastLogURL: URL?
    private var stopButton: NSButton!
    private var allowWindowClose = false
    private var stopInProgress = false
    private var externalMonitor: Timer?

    private lazy var runtimeRoot: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("港航演示中心/Runtime", isDirectory: true)
    }()

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

        [badge, title, subtitle, progress, statusLabel, detailLabel, retryButton, logsButton].forEach(contentRoot.addSubview)

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
            logsButton.widthAnchor.constraint(equalToConstant: 120)
        ])

        window.makeKeyAndOrderFront(nil)
    }

    private func startServices() {
        webView?.removeFromSuperview()
        webView = nil
        retryButton.isHidden = true
        logsButton.isHidden = true
        progress.isHidden = false
        progress.startAnimation(nil)
        ensureService(at: 0)
    }

    private func ensureService(at index: Int) {
        guard index < config.services.count else {
            showSystemUI()
            return
        }
        let service = config.services[index]
        statusLabel.stringValue = "正在连接 \(service.name)"
        detailLabel.stringValue = "检查真实服务与端口契约…"

        probe(service) { [weak self] healthy in
            guard let self else { return }
            if healthy {
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
        guard let url = URL(string: service.healthURL) else {
            completion(false)
            return
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 2.0)
        request.setValue("PortDemoDesktop/1.0", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let http = response as? HTTPURLResponse
            let statusOK = http.map { (200..<300).contains($0.statusCode) } ?? false
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let identityOK = service.healthContains.map { body.contains($0) } ?? true
            DispatchQueue.main.async { completion(statusOK && identityOK) }
        }.resume()
    }

    private func poll(_ service: ServiceConfig, deadline: Date, completion: @escaping (Bool) -> Void) {
        probe(service) { [weak self] healthy in
            guard let self else { return }
            if healthy {
                completion(true)
            } else if Date() >= deadline {
                completion(false)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                    self.poll(service, deadline: deadline, completion: completion)
                }
            }
        }
    }

    private func launch(_ service: ServiceConfig) throws {
        let logURL = runtimeRoot.appendingPathComponent("logs/\(service.id).log")
        lastLogURL = logURL
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        let logHandle = try FileHandle(forWritingTo: logURL)
        try logHandle.seekToEnd()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-lc", "exec \(service.command)"]
        process.currentDirectoryURL = URL(fileURLWithPath: expandedPath(service.workDir), isDirectory: true)
        process.standardOutput = logHandle
        process.standardError = logHandle
        try process.run()
        ownedProcesses.append(process)
        writePID(id: service.id, pid: process.processIdentifier, signature: service.processSignature)
    }

    private func launchExternal(_ external: ExternalConfig) {
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
        window.title = config.name
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showWebLoadError(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showWebLoadError(error)
    }

    private func showWebLoadError(_ error: Error) {
        webView?.removeFromSuperview()
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
    }

    @objc private func retryStartup() {
        statusLabel.textColor = .white
        if let external = config.external { launchExternal(external) }
        else { startServices() }
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
        alert.informativeText = "将核验 PID 与进程签名，停止该系统真实后台进程；不是只关闭表面窗口。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "停止并退出")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        stopInProgress = true
        stopButton.isEnabled = false
        stopButton.title = "正在停止…"
        webView?.isHidden = true
        progress.isHidden = false
        progress.startAnimation(nil)
        statusLabel.stringValue = "正在停止真实后台进程"
        statusLabel.textColor = .white
        detailLabel.stringValue = "正在核验进程树与退出回执…"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = self.stopConfiguredProcesses()
            DispatchQueue.main.async {
                self.progress.stopAnimation(nil)
                self.statusLabel.stringValue = result.remaining == 0 ? "系统已完全停止" : "仍有进程未退出"
                self.detailLabel.stringValue = result.remaining == 0
                    ? "已停止 \(result.stopped) 个核验进程，端口与资源已经释放。"
                    : "已停止 \(result.stopped) 个进程，仍有 \(result.remaining) 个进程未确认退出，请查看日志。"
                if result.remaining == 0 {
                    self.allowWindowClose = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { NSApp.terminate(nil) }
                } else {
                    self.stopInProgress = false
                    self.stopButton.isEnabled = true
                    self.stopButton.title = "■  再次停止并退出"
                    self.webView?.isHidden = false
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

    private func stopConfiguredProcesses() -> (stopped: Int, remaining: Int) {
        let ids: [String]
        if let configured = config.stopServiceIDs, !configured.isEmpty {
            ids = configured
        } else if let external = config.external {
            ids = [external.id]
        } else {
            ids = config.services.map(\.id)
        }

        var snapshots: [Int32: String] = [:]
        var recordFiles: [URL] = []
        for id in ids {
            guard let record = readPID(id: id), isRecordAlive(record) else {
                try? FileManager.default.removeItem(at: pidURL(id: id))
                continue
            }
            recordFiles.append(pidURL(id: id))
            for pid in [record.pid] + descendantPIDs(of: record.pid) {
                let command = processCommand(pid: pid).trimmingCharacters(in: .whitespacesAndNewlines)
                if !command.isEmpty { snapshots[pid] = command }
            }
        }

        for pid in snapshots.keys.sorted() { _ = Darwin.kill(pid, SIGTERM) }
        Thread.sleep(forTimeInterval: 1.2)

        for (pid, expectedCommand) in snapshots {
            guard Darwin.kill(pid, 0) == 0 else { continue }
            let currentCommand = processCommand(pid: pid).trimmingCharacters(in: .whitespacesAndNewlines)
            if currentCommand == expectedCommand { _ = Darwin.kill(pid, SIGKILL) }
        }
        Thread.sleep(forTimeInterval: 0.2)

        var remaining = 0
        for (pid, expectedCommand) in snapshots {
            guard Darwin.kill(pid, 0) == 0 else { continue }
            if processCommand(pid: pid).trimmingCharacters(in: .whitespacesAndNewlines) == expectedCommand {
                remaining += 1
            }
        }
        if remaining == 0 { recordFiles.forEach { try? FileManager.default.removeItem(at: $0) } }
        return (max(0, snapshots.count - remaining), remaining)
    }

    private func descendantPIDs(of rootPID: Int32) -> [Int32] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,ppid="]
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return [] }
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        var children: [Int32: [Int32]] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count >= 2, let pid = Int32(fields[0]), let ppid = Int32(fields[1]) else { continue }
            children[ppid, default: []].append(pid)
        }
        var result: [Int32] = []
        var queue = children[rootPID] ?? []
        while !queue.isEmpty {
            let pid = queue.removeFirst()
            result.append(pid)
            queue.append(contentsOf: children[pid] ?? [])
        }
        return result
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
            process.waitUntilExit()
            return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}

let application = NSApplication.shared
let applicationDelegate = SystemShellDelegate()
application.delegate = applicationDelegate
application.run()
