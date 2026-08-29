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

struct LauncherPIDRecord: Codable {
    let id: String
    let pid: Int32
    let signature: String
    let startedAt: String
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

    func setOnline(_ online: Bool) {
        statusDot.layer?.backgroundColor = (online ? NSColor.systemGreen : NSColor.systemGray).cgColor
        statusLabel.stringValue = online ? "系统在线" : "等待启动"
        statusLabel.textColor = online ? NSColor.systemGreen : NSColor(calibratedWhite: 0.62, alpha: 1)
        openButton.title = online ? "切回系统" : "打开系统"
    }
}

final class LauncherDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var cards: [String: ProjectCardView] = [:]
    private var statusTimer: Timer?
    private var openAllButton: NSButton!
    private var startAllInProgress = false
    private var startGeneration = 0

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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildWindow()
        refreshStatuses()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refreshStatuses()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func buildWindow() {
        let frame = NSRect(x: 0, y: 0, width: 980, height: 720)
        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "港航演示中心"
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

        let stopAll = NSButton(title: "全部停止", target: self, action: #selector(stopAllProjects))
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
        guard let id = sender.identifier?.rawValue, let project = projects.first(where: { $0.id == id }) else { return }
        open(project)
    }

    private func open(_ project: LauncherProject) {
        guard let systemsRoot = Bundle.main.resourceURL?.appendingPathComponent("Systems", isDirectory: true) else { return }
        let appURL = systemsRoot.appendingPathComponent(project.appFile, isDirectory: true)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { [weak self] _, error in
            if let error {
                DispatchQueue.main.async { self?.showAlert(title: "无法打开 \(project.name)", detail: error.localizedDescription) }
            }
        }
    }

    @objc private func openAllProjects() {
        guard !startAllInProgress else { return }
        startAllInProgress = true
        startGeneration += 1
        openAllButton.isEnabled = false
        openAllButton.title = "启动 1/6"

        let order = ["port", "xiaoyi", "energy", "malacca", "mobile", "sailing"]
        startNextProject(order: order, index: 0, generation: startGeneration, failures: [])
    }

    private func startNextProject(order: [String], index: Int, generation: Int, failures: [String]) {
        guard generation == startGeneration else { return }
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
            self.cards[project.id]?.setOnline(online)
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
            completion(hasLiveRecordedProcess(id: pidID))
        } else {
            completion(false)
        }
    }

    @objc private func stopAllProjects() {
        startGeneration += 1
        startAllInProgress = false
        openAllButton?.isEnabled = true
        openAllButton?.title = "全部启动"

        let alert = NSAlert()
        alert.messageText = "停止启动器管理的全部系统？"
        alert.informativeText = "只会停止由本演示中心记录并验证身份的进程，不会关闭其他终端或无关服务。"
        alert.addButton(withTitle: "全部停止")
        alert.addButton(withTitle: "取消")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let pidDir = runtimeRoot.appendingPathComponent("pids", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: pidDir, includingPropertiesForKeys: nil)) ?? []
        let processTable = readProcessTable()
        var managedRecords: [(file: URL, record: LauncherPIDRecord, pids: Set<Int32>)] = []
        var snapshots: [Int32: String] = [:]

        for file in files where file.pathExtension == "json" {
            guard
                let data = try? Data(contentsOf: file),
                let record = try? JSONDecoder().decode(LauncherPIDRecord.self, from: data)
            else {
                try? FileManager.default.removeItem(at: file)
                continue
            }

            guard isRecordAlive(record) else {
                try? FileManager.default.removeItem(at: file)
                continue
            }

            var pids = descendantPIDs(of: record.pid, in: processTable)
            pids.insert(record.pid)
            for pid in pids {
                let command = (processTable[pid]?.command ?? processCommand(pid: pid))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !command.isEmpty { snapshots[pid] = command }
            }
            managedRecords.append((file: file, record: record, pids: pids))
        }

        // Stop every verified descendant as well as its recorded root. Keeping a
        // command snapshot prevents PID reuse from ever targeting an unrelated process.
        for pid in snapshots.keys.sorted(by: >) { _ = Darwin.kill(pid, SIGTERM) }
        Thread.sleep(forTimeInterval: 1.2)

        var forced = 0
        for (pid, command) in snapshots where processStillMatches(pid: pid, command: command) {
            if Darwin.kill(pid, SIGKILL) == 0 { forced += 1 }
        }
        if forced > 0 { Thread.sleep(forTimeInterval: 0.25) }

        let remaining = snapshots.filter { processStillMatches(pid: $0.key, command: $0.value) }
        for item in managedRecords {
            let recordStillRunning = item.pids.contains { pid in
                guard let command = snapshots[pid] else { return false }
                return processStillMatches(pid: pid, command: command)
            }
            if !recordStillRunning { try? FileManager.default.removeItem(at: item.file) }
        }

        for project in projects {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: project.bundleID) {
                app.terminate()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in self?.refreshStatuses() }
        if remaining.isEmpty {
            showAlert(
                title: "全部系统已真实停止",
                detail: "已核验 \(managedRecords.count) 个系统记录，并确认 \(snapshots.count) 个后台及子进程均已退出。\(forced > 0 ? "其中 \(forced) 个进程在超时后已强制结束。" : "")"
            )
        } else {
            showAlert(
                title: "有进程未能停止",
                detail: "为避免误杀其他程序，已保留 \(remaining.count) 个未通过最终身份核验的进程记录，请查看运行日志。"
            )
        }
    }

    @objc private func refreshButtonPressed() { refreshStatuses() }

    private func refreshStatuses() {
        for project in projects {
            if let healthURL = project.healthURL, let url = URL(string: healthURL) {
                var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 1.2)
                request.setValue("PortDemoLauncher/1.0", forHTTPHeaderField: "User-Agent")
                URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
                    let http = response as? HTTPURLResponse
                    let statusOK = http.map { (200..<300).contains($0.statusCode) } ?? false
                    let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    let identityOK = project.healthContains.map { body.contains($0) } ?? true
                    DispatchQueue.main.async { self?.cards[project.id]?.setOnline(statusOK && identityOK) }
                }.resume()
            } else if let pidID = project.pidID {
                cards[project.id]?.setOnline(hasLiveRecordedProcess(id: pidID))
            }
        }
    }

    private func hasLiveRecordedProcess(id: String) -> Bool {
        let file = runtimeRoot.appendingPathComponent("pids/\(id).json")
        guard
            let data = try? Data(contentsOf: file),
            let record = try? JSONDecoder().decode(LauncherPIDRecord.self, from: data),
            isRecordAlive(record)
        else { return false }
        return true
    }

    private func isRecordAlive(_ record: LauncherPIDRecord) -> Bool {
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
        } catch { return "" }
    }

    private func processStillMatches(pid: Int32, command: String) -> Bool {
        guard pid > 1, Darwin.kill(pid, 0) == 0 else { return false }
        return processCommand(pid: pid).trimmingCharacters(in: .whitespacesAndNewlines)
            == command.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func readProcessTable() -> [Int32: (parent: Int32, command: String)] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,ppid=,command="]
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            // Drain the pipe while `ps` is still producing output. Waiting first
            // can deadlock once long command lines fill the pipe buffer.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(data: data, encoding: .utf8) ?? ""
            var table: [Int32: (parent: Int32, command: String)] = [:]
            for line in output.split(separator: "\n") {
                let fields = line.split(maxSplits: 2, whereSeparator: { $0 == " " || $0 == "\t" })
                guard fields.count == 3, let pid = Int32(fields[0]), let parent = Int32(fields[1]) else { continue }
                table[pid] = (parent: parent, command: String(fields[2]))
            }
            return table
        } catch { return [:] }
    }

    private func descendantPIDs(of root: Int32, in table: [Int32: (parent: Int32, command: String)]) -> Set<Int32> {
        var descendants: Set<Int32> = []
        var frontier: [Int32] = [root]
        while let parent = frontier.popLast() {
            for (pid, entry) in table where entry.parent == parent && !descendants.contains(pid) {
                descendants.insert(pid)
                frontier.append(pid)
            }
        }
        return descendants
    }

    private func showAlert(title: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }
}

let application = NSApplication.shared
let applicationDelegate = LauncherDelegate()
application.delegate = applicationDelegate
application.run()

