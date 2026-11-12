import Cocoa
import Darwin

struct LauncherProject {
    let id: String
    let appFile: String
    let bundleID: String
    let name: String
    let subtitle: String
    let symbol: String
    let accent: NSColor
    let healthURL: String?
    let healthContains: String?
    let pidID: String?
}

private struct LauncherServiceConfig: Decodable {
    let id: String
    let workDir: String
    let processSignature: String
    let healthURL: String?

    var managedService: ManagedService {
        ManagedService(id: id, workDir: workDir, processSignature: processSignature, healthURL: healthURL)
    }
}

private struct LauncherSystemConfig: Decodable {
    let services: [LauncherServiceConfig]
    let external: LauncherServiceConfig?
}

final class ProjectCardView: NSView {
    let project: LauncherProject
    let statusDot = NSView()
    let statusLabel = NSTextField(labelWithString: "检查中")
    let openButton = NSButton(title: "打开系统", target: nil, action: nil)

    init(project: LauncherProject) {
        self.project = project
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 17
        layer?.backgroundColor = NSColor(calibratedRed: 0.060, green: 0.098, blue: 0.155, alpha: 0.96).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.09).cgColor

        let iconBackdrop = NSView()
        iconBackdrop.wantsLayer = true
        iconBackdrop.layer?.cornerRadius = 18
        iconBackdrop.layer?.backgroundColor = project.accent.withAlphaComponent(0.16).cgColor
        iconBackdrop.translatesAutoresizingMaskIntoConstraints = false

        let iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: project.symbol, accessibilityDescription: project.name)
        iconView.contentTintColor = project.accent
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = NSTextField(labelWithString: project.name)
        nameLabel.font = NSFont.systemFont(ofSize: 17, weight: .bold)
        nameLabel.textColor = .white
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        let subtitleLabel = NSTextField(wrappingLabelWithString: project.subtitle)
        subtitleLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
        subtitleLabel.textColor = NSColor(calibratedWhite: 0.67, alpha: 1)
        subtitleLabel.maximumNumberOfLines = 2
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 4
        statusDot.layer?.backgroundColor = NSColor.systemGray.cgColor
        statusDot.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        statusLabel.textColor = NSColor(calibratedWhite: 0.62, alpha: 1)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        openButton.bezelStyle = .rounded
        openButton.bezelColor = project.accent
        openButton.contentTintColor = .white
        openButton.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        openButton.translatesAutoresizingMaskIntoConstraints = false

        [iconBackdrop, iconView, nameLabel, subtitleLabel, statusDot, statusLabel, openButton].forEach(addSubview)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 154),
            iconBackdrop.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            iconBackdrop.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            iconBackdrop.widthAnchor.constraint(equalToConstant: 48),
            iconBackdrop.heightAnchor.constraint(equalToConstant: 48),
            iconView.centerXAnchor.constraint(equalTo: iconBackdrop.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBackdrop.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 25),
            iconView.heightAnchor.constraint(equalToConstant: 25),
            nameLabel.leadingAnchor.constraint(equalTo: iconBackdrop.trailingAnchor, constant: 13),
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            subtitleLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 5),
            subtitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            statusDot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 19),
            statusDot.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -22),
            statusDot.widthAnchor.constraint(equalToConstant: 8),
            statusDot.heightAnchor.constraint(equalToConstant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: statusDot.trailingAnchor, constant: 7),
            statusLabel.centerYAnchor.constraint(equalTo: statusDot.centerYAnchor),
            openButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -17),
            openButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            openButton.widthAnchor.constraint(equalToConstant: 100),
            openButton.heightAnchor.constraint(equalToConstant: 30)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func setStatus(serviceOnline: Bool, appRunning: Bool) {
        let color: NSColor
        if serviceOnline && appRunning {
            color = .systemGreen
            statusLabel.stringValue = "系统在线"
        } else if serviceOnline {
            color = .systemOrange
            statusLabel.stringValue = "后台仍在运行"
        } else if appRunning {
            color = .systemOrange
            statusLabel.stringValue = "窗口已打开 · 服务未就绪"
        } else {
            color = .systemGray
            statusLabel.stringValue = "等待启动"
        }
        statusDot.layer?.backgroundColor = color.cgColor
        statusLabel.textColor = color
        openButton.title = appRunning ? "切回系统" : "打开系统"
    }
}

final class LauncherDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var cards: [String: ProjectCardView] = [:]
    private var statusTimer: Timer?
    private var openAllButton: NSButton!
    private var stopAllButton: NSButton!
    private var startAllInProgress = false
    private var startGeneration = 0
    private var lifecycleGeneration = 0
    private var statusGeneration = 0
    private var stopAllInProgress = false
    private var isTerminating = false
    private var pendingOpenRequests: Set<UUID> = []
    private var cancelledOpenApplications: [NSRunningApplication] = []

    private let projects: [LauncherProject] = [
        LauncherProject(
            id: "mobile", appFile: "PortAI移动端.app", bundleID: "com.wenjiayi.portdemo.mobile",
            name: "PortAI 移动端", subtitle: "Flutter 移动决策台 · 真实 Web API 联动",
            symbol: "iphone.gen3", accent: NSColor(calibratedRed: 0.21, green: 0.67, blue: 1.0, alpha: 1),
            healthURL: "http://127.0.0.1:8765/", healthContains: "PortAI", pidID: nil
        ),
        LauncherProject(
            id: "port", appFile: "港口数字孪生V3.2.app", bundleID: "com.wenjiayi.portdemo.digitaltwin",
            name: "港口数字孪生 V3.2", subtitle: "12 方法决策中枢 · 可审计 RL 与小懿联动",
            symbol: "shippingbox.fill", accent: NSColor(calibratedRed: 0.22, green: 0.83, blue: 0.73, alpha: 1),
            healthURL: "http://127.0.0.1:8000/health/live", healthContains: "alive", pidID: nil
        ),
        LauncherProject(
            id: "malacca", appFile: "马六甲港口推演.app", bundleID: "com.wenjiayi.portdemo.malacca",
            name: "马六甲港口推演", subtitle: "多港韧性沙盘 · 强化学习与人机协同",
            symbol: "map.fill", accent: NSColor(calibratedRed: 1.0, green: 0.59, blue: 0.24, alpha: 1),
            healthURL: "http://127.0.0.1:5174/api/rl/health", healthContains: "malacca-reference-rl", pidID: nil
        ),
        LauncherProject(
            id: "sailing", appFile: "航行模拟器.app", bundleID: "com.wenjiayi.portdemo.sailing",
            name: "航行模拟器", subtitle: "Godot 三维航行 · 五基线策略验证",
            symbol: "ferry.fill", accent: NSColor(calibratedRed: 0.47, green: 0.58, blue: 1.0, alpha: 1),
            healthURL: nil, healthContains: nil, pidID: "sailing"
        ),
        LauncherProject(
            id: "energy", appFile: "能碳驾驶舱.app", bundleID: "com.wenjiayi.portdemo.energy",
            name: "能碳驾驶舱", subtitle: "港口能源调度 · 实时模拟与准入门禁",
            symbol: "leaf.fill", accent: NSColor(calibratedRed: 0.42, green: 0.88, blue: 0.38, alpha: 1),
            healthURL: "http://127.0.0.1:5173/", healthContains: "港口能碳", pidID: nil
        ),
        LauncherProject(
            id: "xiaoyi", appFile: "小懿AI.app", bundleID: "com.wenjiayi.portdemo.xiaoyi",
            name: "小懿 AI", subtitle: "本地模型与 RAG · 六系统联动入口",
            symbol: "sparkles", accent: NSColor(calibratedRed: 0.92, green: 0.43, blue: 1.0, alpha: 1),
            healthURL: "http://127.0.0.1:8010/health", healthContains: "小懿", pidID: nil
        )
    ]

    private lazy var runtimeRoot: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("港航演示中心/Runtime", isDirectory: true)
    }()

    private lazy var processRuntime = ManagedProcessRuntime(runtimeRoot: runtimeRoot)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        _ = processRuntime
        buildWindow()
        refreshStatuses()
        startStatusTimer()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        isTerminating = true
        startGeneration += 1
        lifecycleGeneration += 1
        statusGeneration += 1
        statusTimer?.invalidate()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Let a requested stop finish before the controller itself disappears.
        if stopAllInProgress { return .terminateCancel }
        if isTerminating { return .terminateLater }
        if !pendingOpenRequests.isEmpty {
            isTerminating = true
            startAllInProgress = false
            startGeneration += 1
            lifecycleGeneration += 1
            statusGeneration += 1
            statusTimer?.invalidate()
            openAllButton?.isEnabled = true
            openAllButton?.title = "全部启动"
            waitForCancelledOpensBeforeTermination(deadline: Date().addingTimeInterval(12))
            return .terminateLater
        }
        return .terminateNow
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if stopAllInProgress { return false }
        if !pendingOpenRequests.isEmpty || isTerminating {
            NSApp.terminate(nil)
            return false
        }
        return true
    }

    private func waitForCancelledOpensBeforeTermination(deadline: Date) {
        if pendingOpenRequests.isEmpty && cancelledOpenApplications.allSatisfy({ $0.isTerminated }) {
            NSApp.reply(toApplicationShouldTerminate: true)
            return
        }
        guard Date() < deadline else {
            isTerminating = false
            NSApp.reply(toApplicationShouldTerminate: false)
            startStatusTimer()
            showAlert(title: "正在取消打开请求", detail: "仍有系统打开或退出请求尚未结束，请稍后再次退出演示中心。")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.waitForCancelledOpensBeforeTermination(deadline: deadline)
        }
    }

    private func startStatusTimer() {
        statusTimer?.invalidate()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refreshStatuses()
        }
    }

    private func buildWindow() {
        let frame = NSRect(x: 0, y: 0, width: 980, height: 720)
        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "港航演示中心"
        window.delegate = self
        window.minSize = NSSize(width: 850, height: 650)
        window.center()

        let root = NSView(frame: frame)
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(calibratedRed: 0.025, green: 0.047, blue: 0.082, alpha: 1).cgColor
        window.contentView = root

        let eyebrow = NSTextField(labelWithString: "PORT INTELLIGENCE · DESKTOP SUITE")
        eyebrow.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        eyebrow.textColor = NSColor(calibratedRed: 0.27, green: 0.77, blue: 1.0, alpha: 1)
        eyebrow.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "港航演示中心")
        title.font = NSFont.systemFont(ofSize: 31, weight: .bold)
        title.textColor = .white
        title.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = NSTextField(labelWithString: "六个独立系统 · 一键启动 · 本地真实联动")
        subtitle.font = NSFont.systemFont(ofSize: 14, weight: .regular)
        subtitle.textColor = NSColor(calibratedWhite: 0.67, alpha: 1)
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        openAllButton = NSButton(title: "全部启动", target: self, action: #selector(openAllProjects))
        let openAll = openAllButton!
        openAll.bezelStyle = .rounded
        openAll.bezelColor = NSColor(calibratedRed: 0.10, green: 0.56, blue: 0.98, alpha: 1)
        openAll.contentTintColor = .white
        openAll.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        openAll.translatesAutoresizingMaskIntoConstraints = false

        stopAllButton = NSButton(title: "全部停止", target: self, action: #selector(stopAllProjects))
        let stopAll = stopAllButton!
        stopAll.bezelStyle = .rounded
        stopAll.bezelColor = NSColor(calibratedRed: 0.58, green: 0.20, blue: 0.24, alpha: 1)
        stopAll.contentTintColor = .white
        stopAll.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        stopAll.translatesAutoresizingMaskIntoConstraints = false

        let refresh = NSButton(image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "刷新状态")!, target: self, action: #selector(refreshButtonPressed))
        refresh.bezelStyle = .rounded
        refresh.toolTip = "刷新运行状态"
        refresh.translatesAutoresizingMaskIntoConstraints = false

        let gridRows: [[NSView]] = stride(from: 0, to: projects.count, by: 2).map { index in
            let left = makeCard(projects[index])
            let right = makeCard(projects[index + 1])
            return [left, right]
        }
        let grid = NSGridView(views: gridRows)
        grid.rowSpacing = 15
        grid.columnSpacing = 15
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.column(at: 0).width = 435
        grid.column(at: 1).width = 435

        let footer = NSTextField(labelWithString: "本地独立窗口 · 无浏览器地址栏 · 服务身份与端口冲突保护")
        footer.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        footer.textColor = NSColor(calibratedWhite: 0.45, alpha: 1)
        footer.alignment = .center
        footer.translatesAutoresizingMaskIntoConstraints = false

        [eyebrow, title, subtitle, openAll, stopAll, refresh, grid, footer].forEach(root.addSubview)

        NSLayoutConstraint.activate([
            eyebrow.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 42),
            eyebrow.topAnchor.constraint(equalTo: root.topAnchor, constant: 29),
            title.leadingAnchor.constraint(equalTo: eyebrow.leadingAnchor),
            title.topAnchor.constraint(equalTo: eyebrow.bottomAnchor, constant: 7),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 5),
            refresh.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -42),
            refresh.centerYAnchor.constraint(equalTo: openAll.centerYAnchor),
            refresh.widthAnchor.constraint(equalToConstant: 36),
            openAll.trailingAnchor.constraint(equalTo: refresh.leadingAnchor, constant: -10),
            openAll.topAnchor.constraint(equalTo: root.topAnchor, constant: 48),
            openAll.widthAnchor.constraint(equalToConstant: 108),
            openAll.heightAnchor.constraint(equalToConstant: 35),
            stopAll.trailingAnchor.constraint(equalTo: openAll.leadingAnchor, constant: -10),
            stopAll.centerYAnchor.constraint(equalTo: openAll.centerYAnchor),
            stopAll.widthAnchor.constraint(equalToConstant: 108),
            stopAll.heightAnchor.constraint(equalToConstant: 35),
            grid.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 25),
            grid.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            grid.bottomAnchor.constraint(lessThanOrEqualTo: footer.topAnchor, constant: -14),
            footer.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16)
        ])

        window.makeKeyAndOrderFront(nil)
    }

    private func makeCard(_ project: LauncherProject) -> ProjectCardView {
        let card = ProjectCardView(project: project)
        card.openButton.target = self
        card.openButton.action = #selector(openProject(_:))
        card.openButton.identifier = NSUserInterfaceItemIdentifier(project.id)
        cards[project.id] = card
        return card
    }

    @objc private func openProject(_ sender: NSButton) {
        guard !stopAllInProgress, !isTerminating else { return }
        guard let id = sender.identifier?.rawValue, let project = projects.first(where: { $0.id == id }) else { return }
        open(project)
    }

    private func open(_ project: LauncherProject) {
        guard !stopAllInProgress, !isTerminating else { return }
        guard let systemsRoot = Bundle.main.resourceURL?.appendingPathComponent("Systems", isDirectory: true) else { return }
        let appURL = systemsRoot.appendingPathComponent(project.appFile, isDirectory: true)
        let generation = lifecycleGeneration
        let requestID = UUID()
        pendingOpenRequests.insert(requestID)

        let executableURL = appURL.appendingPathComponent("Contents/MacOS/SystemShell")
        let modifiedAt = try? executableURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let staleApplications = NSRunningApplication.runningApplications(withBundleIdentifier: project.bundleID)
            .filter {
                !$0.isTerminated && requiresFreshApplicationLaunch(
                    launchDate: $0.launchDate,
                    executableModifiedAt: modifiedAt
                )
            }
        if !staleApplications.isEmpty {
            staleApplications.forEach { $0.terminate() }
            waitForStaleApplicationsToExit(
                staleApplications,
                project: project,
                appURL: appURL,
                generation: generation,
                requestID: requestID,
                deadline: Date().addingTimeInterval(8)
            )
            return
        }

        launchInstalledApplication(
            project,
            appURL: appURL,
            generation: generation,
            requestID: requestID
        )
    }

    private func waitForStaleApplicationsToExit(
        _ applications: [NSRunningApplication],
        project: LauncherProject,
        appURL: URL,
        generation: Int,
        requestID: UUID,
        deadline: Date
    ) {
        guard generation == lifecycleGeneration, !stopAllInProgress, !isTerminating else {
            pendingOpenRequests.remove(requestID)
            return
        }
        if applications.allSatisfy(\.isTerminated) {
            launchInstalledApplication(
                project,
                appURL: appURL,
                generation: generation,
                requestID: requestID
            )
            return
        }
        guard Date() < deadline else {
            applications.filter { !$0.isTerminated }.forEach { _ = $0.forceTerminate() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self else { return }
                guard applications.allSatisfy(\.isTerminated) else {
                    self.pendingOpenRequests.remove(requestID)
                    self.showAlert(
                        title: "旧版 \(project.name) 未能退出",
                        detail: "已阻止继续激活旧界面；请再次点击“打开系统”重试。"
                    )
                    return
                }
                self.launchInstalledApplication(
                    project,
                    appURL: appURL,
                    generation: generation,
                    requestID: requestID
                )
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.waitForStaleApplicationsToExit(
                applications,
                project: project,
                appURL: appURL,
                generation: generation,
                requestID: requestID,
                deadline: deadline
            )
        }
    }

    private func launchInstalledApplication(
        _ project: LauncherProject,
        appURL: URL,
        generation: Int,
        requestID: UUID
    ) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { [weak self] app, error in
            DispatchQueue.main.async {
                guard let self else {
                    app?.terminate()
                    return
                }
                self.pendingOpenRequests.remove(requestID)
                guard generation == self.lifecycleGeneration, !self.stopAllInProgress, !self.isTerminating else {
                    if self.isTerminating, let app { self.cancelledOpenApplications.append(app) }
                    app?.terminate()
                    return
                }
                if let error {
                    self.showAlert(title: "无法打开 \(project.name)", detail: error.localizedDescription)
                }
            }
        }
    }

    @objc private func openAllProjects() {
        guard !startAllInProgress, !stopAllInProgress, !isTerminating else { return }
        startAllInProgress = true
        startGeneration += 1
        openAllButton.isEnabled = false
        openAllButton.title = "启动 1/6"

        let order = ["port", "xiaoyi", "energy", "malacca", "mobile", "sailing"]
        startNextProject(order: order, index: 0, generation: startGeneration, failures: [])
    }

    private func startNextProject(order: [String], index: Int, generation: Int, failures: [String]) {
        guard generation == startGeneration, !stopAllInProgress, !isTerminating else { return }
        guard index < order.count else {
            startAllInProgress = false
            openAllButton.isEnabled = true
            openAllButton.title = "全部启动"
            refreshStatuses()
            if failures.isEmpty {
                showAlert(title: "六个系统均已真实就绪", detail: "已按依赖顺序完成启动，每一步均通过服务身份与健康回执核验。")
            } else {
                showAlert(title: "部分系统未能就绪", detail: "已完成分阶段启动，但以下系统未在时限内通过核验：\(failures.joined(separator: "、"))。")
            }
            return
        }

        guard let project = projects.first(where: { $0.id == order[index] }) else {
            startNextProject(order: order, index: index + 1, generation: generation, failures: failures)
            return
        }

        openAllButton.title = "启动 \(index + 1)/\(order.count)"
        open(project)
        let timeout: TimeInterval
        switch project.id {
        case "xiaoyi": timeout = 90
        case "energy", "malacca": timeout = 75
        case "port", "mobile": timeout = 60
        default: timeout = 45
        }
        waitForProject(project, deadline: Date().addingTimeInterval(timeout), generation: generation) { [weak self] online in
            guard let self, generation == self.startGeneration else { return }
            self.cards[project.id]?.setStatus(serviceOnline: online, appRunning: self.isSystemApplicationRunning(project))
            var nextFailures = failures
            if !online { nextFailures.append(project.name) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.startNextProject(order: order, index: index + 1, generation: generation, failures: nextFailures)
            }
        }
    }

    private func waitForProject(
        _ project: LauncherProject,
        deadline: Date,
        generation: Int,
        completion: @escaping (Bool) -> Void
    ) {
        guard generation == startGeneration else { return }
        probeProject(project) { [weak self] online in
            guard let self, generation == self.startGeneration else { return }
            if online {
                completion(true)
            } else if Date() >= deadline {
                completion(false)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    self.waitForProject(project, deadline: deadline, generation: generation, completion: completion)
                }
            }
        }
    }

    private func probeProject(_ project: LauncherProject, completion: @escaping (Bool) -> Void) {
        if let healthURL = project.healthURL, let url = URL(string: healthURL) {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 1.8)
            request.setValue("PortDemoLauncher/1.0", forHTTPHeaderField: "User-Agent")
            URLSession.shared.dataTask(with: request) { data, response, _ in
                let http = response as? HTTPURLResponse
                let statusOK = http.map { (200..<300).contains($0.statusCode) } ?? false
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let identityOK = project.healthContains.map { body.contains($0) } ?? true
                DispatchQueue.main.async { completion(statusOK && identityOK) }
            }.resume()
        } else if let pidID = project.pidID {
            let service = loadManagedServices().services.first { $0.id == pidID }
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let online = service.map { self?.processRuntime.isRunning($0) ?? false } ?? false
                DispatchQueue.main.async { completion(online) }
            }
        } else {
            completion(false)
        }
    }

    private func installedSystemURL(_ project: LauncherProject) -> URL? {
        Bundle.main.resourceURL?
            .appendingPathComponent("Systems", isDirectory: true)
            .appendingPathComponent(project.appFile, isDirectory: true)
    }

    private func runningSystemApplications() -> [NSRunningApplication] {
        projects.flatMap { project in
            NSRunningApplication.runningApplications(withBundleIdentifier: project.bundleID)
                .filter { !$0.isTerminated }
        }
    }

    private func isSystemApplicationRunning(_ project: LauncherProject) -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: project.bundleID)
            .contains { !$0.isTerminated }
    }

    private func loadManagedServices() -> (services: [ManagedService], errors: [String]) {
        var services: [String: ManagedService] = [:]
        var errors: [String] = []
        for project in projects {
            guard let appURL = installedSystemURL(project) else {
                errors.append("无法定位 \(project.name) 的应用配置")
                continue
            }
            let configURL = appURL.appendingPathComponent("Contents/Resources/system.json")
            do {
                let config = try JSONDecoder().decode(LauncherSystemConfig.self, from: Data(contentsOf: configURL))
                let configured = config.services + (config.external.map { [$0] } ?? [])
                for item in configured {
                    let service = item.managedService
                    if let previous = services[item.id],
                       previous.workDir != service.workDir || previous.processSignature != service.processSignature
                        || previous.healthURL != service.healthURL {
                        errors.append("共享服务 \(item.id) 的配置不一致")
                        continue
                    }
                    services[item.id] = service
                }
            } catch {
                errors.append("\(project.name) 配置读取失败：\(error.localizedDescription)")
            }
        }
        return (services.values.sorted { $0.id < $1.id }, errors)
    }

    @objc private func stopAllProjects() {
        guard !stopAllInProgress, !isTerminating else { return }
        let alert = NSAlert()
        alert.messageText = "停止启动器管理的全部系统？"
        alert.informativeText = "将先关闭各系统窗口，再停止已登记端口中、工作目录属于对应项目的后台及子进程；不会清理项目目录之外的同端口进程。"
        alert.addButton(withTitle: "全部停止")
        alert.addButton(withTitle: "取消")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        stopAllInProgress = true
        startAllInProgress = false
        startGeneration += 1
        lifecycleGeneration += 1
        statusGeneration += 1
        let generation = lifecycleGeneration
        statusTimer?.invalidate()
        statusTimer = nil
        openAllButton.isEnabled = false
        openAllButton.title = "正在停止…"
        stopAllButton.isEnabled = false
        cards.values.forEach { $0.openButton.isEnabled = false }

        // Quiesce each shell before stopping its services. Otherwise its health
        // monitor can launch a replacement after the process snapshot is taken.
        let applications = runningSystemApplications()
        applications.forEach { $0.terminate() }
        let configured = loadManagedServices()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.waitForSystemApplicationsToExit(
                deadline: Date().addingTimeInterval(6),
                generation: generation,
                requestedPIDs: Set(applications.map(\.processIdentifier))
            )
            let result = self.processRuntime.stop(
                configured.services,
                recoverProjectListeners: true
            )
            // A shell may have refused the first quit because its conservative
            // per-window stop could not recognize an orphaned wrapper tree.
            // After the global runtime has released the registered project
            // ports, ask those known bundle IDs to quit again. If a shell still
            // does not leave, force-terminate only that registered UI process;
            // the service processes have already gone through identity checks.
            self.waitForSystemApplicationsToExit(
                deadline: Date().addingTimeInterval(3),
                generation: generation,
                requestedPIDs: []
            )
            DispatchQueue.main.sync {
                guard generation == self.lifecycleGeneration else { return }
                self.runningSystemApplications().forEach { _ = $0.forceTerminate() }
            }
            self.waitForSystemApplicationsToExit(
                deadline: Date().addingTimeInterval(2),
                generation: generation,
                requestedPIDs: []
            )
            DispatchQueue.main.async {
                guard generation == self.lifecycleGeneration else { return }
                self.finishStopping(result, configurationErrors: configured.errors)
            }
        }
    }

    // Runs only on the background stop queue; main-thread snapshots keep UI and
    // pending NSWorkspace completions synchronized without blocking the UI.
    private func waitForSystemApplicationsToExit(
        deadline: Date,
        generation: Int,
        requestedPIDs: Set<Int32>
    ) {
        var requested = requestedPIDs
        while Date() < deadline {
            var settled = false
            DispatchQueue.main.sync {
                guard generation == self.lifecycleGeneration else {
                    settled = true
                    return
                }
                let applications = self.runningSystemApplications()
                for app in applications where !requested.contains(app.processIdentifier) {
                    requested.insert(app.processIdentifier)
                    app.terminate()
                }
                settled = applications.isEmpty && self.pendingOpenRequests.isEmpty
            }
            if settled { return }
            Thread.sleep(forTimeInterval: 0.15)
        }
    }

    private func finishStopping(_ result: ManagedStopResult, configurationErrors: [String]) {
        let remainingApplications = runningSystemApplications()
        let errors = configurationErrors + result.errors
        let complete = result.remaining == 0 && result.remainingPorts.isEmpty
            && remainingApplications.isEmpty && pendingOpenRequests.isEmpty && errors.isEmpty
        stopAllInProgress = false
        openAllButton.isEnabled = true
        openAllButton.title = "全部启动"
        stopAllButton.isEnabled = true
        cards.values.forEach { $0.openButton.isEnabled = true }
        startStatusTimer()
        refreshStatuses()

        if complete {
            showAlert(
                title: "全部系统已真实停止",
                detail: "已核验全部系统配置，停止 \(result.stopped) 个后台及子进程；系统窗口均已退出，目标端口无残留监听。"
            )
        } else {
            var details = ["未确认退出的后台进程：\(result.remaining)，系统窗口：\(remainingApplications.count)，待完成打开请求：\(pendingOpenRequests.count)。"]
            if !result.remainingPorts.isEmpty {
                details.append("仍在监听的端口：\(result.remainingPorts.map(String.init).joined(separator: "、"))。")
            }
            if !errors.isEmpty { details.append(errors.joined(separator: "\n")) }
            showAlert(title: "部分系统尚未完全停止", detail: details.joined(separator: "\n"))
        }
    }

    @objc private func refreshButtonPressed() { refreshStatuses() }

    private func refreshStatuses() {
        guard !stopAllInProgress, !isTerminating else { return }
        statusGeneration += 1
        let generation = statusGeneration
        for project in projects {
            probeProject(project) { [weak self] online in
                guard let self, generation == self.statusGeneration,
                      !self.stopAllInProgress, !self.isTerminating else { return }
                self.cards[project.id]?.setStatus(
                    serviceOnline: online,
                    appRunning: self.isSystemApplicationRunning(project)
                )
            }
        }
    }

    private func showAlert(title: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }
}

@main
struct LauncherApplication {
    static func main() {
        let application = NSApplication.shared
        let applicationDelegate = LauncherDelegate()
        application.delegate = applicationDelegate
        withExtendedLifetime(applicationDelegate) { application.run() }
    }
}
