import Foundation
import Darwin

struct ManagedService {
    let id: String
    let workDir: String
    let processSignature: String
    let healthURL: String?
}

struct ManagedProcessIdentity: Codable, Equatable {
    let pid: Int32
    let parentPID: Int32
    let command: String
    let startedAt: String
    let workDir: String
    let processStartToken: String
}

struct ManagedStopResult {
    var stopped = 0
    var remaining = 0
    var protectedServiceIDs: [String] = []
    var remainingPorts: [Int] = []
    var errors: [String] = []
}

/// Shared by the individual system windows and the desktop launcher.
/// Discovery needs both the configured process signature and the real project
/// directory. A listening port alone never authorizes terminating a process.
final class ManagedProcessRuntime {
    private struct Record: Codable {
        let id: String
        let pid: Int32
        let signature: String
        let startedAt: String
        let fullCommand: String?
        let processStartToken: String?
        let workDir: String?
        let identities: [ManagedProcessIdentity]?
    }

    private struct Lease: Codable {
        let ownerID: String
        let ownerPID: Int32
        let processStartToken: String
        let serviceIDs: [String]
    }

    private let runtimeRoot: URL
    private let fileManager = FileManager.default

    init(runtimeRoot: URL) {
        self.runtimeRoot = runtimeRoot
    }

    func acquireLease(ownerID: String, serviceIDs: [String]) -> Bool {
        guard let token = birthToken(getpid()) else { return false }
        let lease = Lease(ownerID: ownerID, ownerPID: getpid(),
                          processStartToken: token, serviceIDs: Array(Set(serviceIDs)).sorted())
        do {
            try fileManager.createDirectory(at: leaseDirectory, withIntermediateDirectories: true)
            try JSONEncoder().encode(lease).write(to: leaseURL(ownerID), options: .atomic)
            return true
        } catch { return false }
    }

    func releaseLease(ownerID: String) {
        // An older window must not remove the lease of a replacement window.
        guard let data = try? Data(contentsOf: leaseURL(ownerID)),
              let lease = try? JSONDecoder().decode(Lease.self, from: data),
              lease.ownerPID == getpid(), lease.processStartToken == birthToken(getpid()) else { return }
        try? fileManager.removeItem(at: leaseURL(ownerID))
    }

    func leasedServiceIDs(excludingOwnerID: String? = nil) -> Set<String> {
        let files = (try? fileManager.contentsOfDirectory(at: leaseDirectory,
                     includingPropertiesForKeys: nil)) ?? []
        var result = Set<String>()
        for url in files where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let lease = try? JSONDecoder().decode(Lease.self, from: data),
                  lease.ownerID != excludingOwnerID,
                  birthToken(lease.ownerPID) == lease.processStartToken else { continue }
            result.formUnion(lease.serviceIDs)
        }
        return result
    }

    func discover(_ service: ManagedService, recordedPID: Int32? = nil) -> [ManagedProcessIdentity] {
        discover(service, recordedPID: recordedPID, table: processTable())
    }

    @discardableResult
    func adopt(_ service: ManagedService, preferredPID: Int32? = nil) -> Bool {
        let table = processTable()
        let roots = discover(service, recordedPID: preferredPID, table: table)
        guard !roots.isEmpty else { return false }
        let identities = expandedTree(roots, service: service, table: table)
        let preferred = roots.first(where: { $0.pid == preferredPID })
        let savedPID = readRecord(service.id)?.pid
        let primary = preferred ?? roots.first(where: { $0.pid == savedPID }) ?? roots[0]
        return writeRecord(service, primary: primary, identities: identities)
    }

    func isRunning(_ service: ManagedService) -> Bool {
        !discover(service).isEmpty
    }

    /// Call outside the main UI thread. Protected services are intentionally
    /// retained and do not count as failures. Unrelated listeners do count as
    /// unresolved ports, but are never signalled.
    func stop(
        _ services: [ManagedService],
        protectedServiceIDs: Set<String> = [],
        recoverProjectListeners: Bool = false
    ) -> ManagedStopResult {
        var result = ManagedStopResult()
        result.protectedServiceIDs = services.map(\.id).filter(protectedServiceIDs.contains).sorted()
        let selected = services.filter { !protectedServiceIDs.contains($0.id) }
        let table = processTable()
        var targets: [Int32: ManagedProcessIdentity] = [:]
        for service in selected {
            let roots = discover(
                service,
                recordedPID: nil,
                table: table,
                trustRegisteredPortInsideProject: recoverProjectListeners
            )
            let identities = expandedTree(roots, service: service, table: table)
            if let primary = roots.first {
                _ = writeRecord(service, primary: primary, identities: identities)
            }
            for identity in identities { targets[identity.pid] = identity }
        }
        // Children first, retaining the exact command and microsecond birth
        // identity from before shutdown for every signal and post-check.
        let ordered = targets.values.sorted {
            depth($0.pid, table: table) > depth($1.pid, table: table)
        }
        for target in ordered {
            if exactIdentityStillAlive(target) { _ = Darwin.kill(target.pid, SIGTERM) }
        }
        waitForExit(Array(targets.values), timeout: 2.0)
        for target in ordered {
            if exactIdentityStillAlive(target) { _ = Darwin.kill(target.pid, SIGKILL) }
        }
        waitForExit(Array(targets.values), timeout: 1.0)

        let survivors = targets.values.filter { birthToken($0.pid) == $0.processStartToken }
        result.stopped = targets.count - survivors.count
        result.remaining = survivors.count
        for target in survivors {
            result.errors.append("进程 \(target.pid) 尚未退出或身份在停止期间发生变化。")
        }
        var remainingPorts = Set<Int>()
        for service in selected {
            let ownedStillAlive = survivors.contains { isWithin($0.workDir, root: service.workDir) }
            var portStillInUse = false
            if let port = portNumber(service), let listeners = listenerPIDs(port) {
                portStillInUse = !listeners.isEmpty
                if portStillInUse {
                    remainingPorts.insert(port)
                    let hasCountedSurvivor = survivors.contains {
                        listeners.contains($0.pid) && birthToken($0.pid) == $0.processStartToken
                    }
                    if !hasCountedSurvivor {
                        result.errors.append("\(service.id) 的端口 \(port) 仍被未获授权的进程占用，已保留该进程。")
                        result.remaining += 1
                    }
                }
            } else if portNumber(service) != nil {
                portStillInUse = true
                result.remaining += 1
                result.errors.append("无法核验 \(service.id) 的监听端口，未声明停止完成。")
            }
            if !ownedStillAlive && !portStillInUse {
                try? fileManager.removeItem(at: recordURL(service.id))
            }
        }
        result.remainingPorts = remainingPorts.sorted()
        return result
    }

    private func discover(
        _ service: ManagedService,
        recordedPID: Int32?,
        table: [Int32: String],
        trustRegisteredPortInsideProject: Bool = false
    ) -> [ManagedProcessIdentity] {
        var found: [Int32: ManagedProcessIdentity] = [:]
        let excluded = ownAncestors()
        func add(_ pid: Int32, requireSignature: Bool = true) {
            guard !excluded.contains(pid), let identity = identity(pid, command: table[pid]),
                  isWithin(identity.workDir, root: service.workDir),
                  !requireSignature || identity.command.contains(service.processSignature) else { return }
            found[pid] = identity
        }
        if let pid = recordedPID { add(pid) }
        if let record = readRecord(service.id), record.signature == service.processSignature {
            if let token = record.processStartToken {
                if token == birthToken(record.pid), record.fullCommand == table[record.pid] { add(record.pid) }
            } else {
                // Legacy records lack a birth token, so accept them only after
                // checking the current signature and native project directory.
                add(record.pid)
            }
            for saved in record.identities ?? [] where saved.processStartToken == birthToken(saved.pid)
                && saved.command == table[saved.pid] {
                add(saved.pid, requireSignature: false)
            }
        }
        if let port = portNumber(service), let listeners = listenerPIDs(port) {
            for listener in listeners {
                guard let listeningIdentity = identity(listener, command: table[listener]),
                      isWithin(listeningIdentity.workDir, root: service.workDir) else { continue }
                var pid = listener
                var visited = Set<Int32>()
                while pid > 1 && visited.insert(pid).inserted {
                    // "全部停止" is allowed to recover an orphaned launcher
                    // tree when the exact registered loopback port is owned by a
                    // process whose real cwd is inside the configured project.
                    // This handles wrappers such as make -> start_demo.sh ->
                    // pnpm/vite after the original signature process has exited.
                    // A same-port process outside the project is still never
                    // signalled. Individual system shutdown keeps the stricter
                    // signature rule unless it already adopted the process.
                    add(pid, requireSignature: !trustRegisteredPortInsideProject)
                    guard let info = processInfo(pid) else { break }
                    pid = Int32(info.pbi_ppid)
                }
            }
        } else if service.healthURL == nil {
            for (pid, command) in table where command.contains(service.processSignature) { add(pid) }
        }
        return found.values.sorted { $0.pid < $1.pid }
    }

    private func expandedTree(_ roots: [ManagedProcessIdentity], service: ManagedService,
                              table: [Int32: String]) -> [ManagedProcessIdentity] {
        var children: [Int32: [Int32]] = [:]
        for pid in table.keys {
            guard let info = processInfo(pid) else { continue }
            children[Int32(info.pbi_ppid), default: []].append(pid)
        }
        var found = Dictionary(uniqueKeysWithValues: roots.map { ($0.pid, $0) })
        var pending = roots.map(\.pid)
        var visited = Set<Int32>()
        let excluded = ownAncestors()
        while let pid = pending.popLast() {
            guard visited.insert(pid).inserted else { continue }
            for child in children[pid] ?? [] {
                guard !excluded.contains(child), let value = identity(child, command: table[child]),
                      isWithin(value.workDir, root: service.workDir) else { continue }
                found[child] = value
                pending.append(child)
            }
        }
        return found.values.sorted { $0.pid < $1.pid }
    }

    private func processInfo(_ pid: Int32) -> proc_bsdinfo? {
        guard pid > 1 else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
              info.pbi_status != UInt32(SZOMB) else { return nil }
        return info
    }

    private func birthToken(_ pid: Int32) -> String? {
        guard let info = processInfo(pid) else { return nil }
        return "\(info.pbi_start_tvsec).\(info.pbi_start_tvusec)"
    }

    private func identity(_ pid: Int32, command: String? = nil) -> ManagedProcessIdentity? {
        guard let info = processInfo(pid) else { return nil }
        let token = "\(info.pbi_start_tvsec).\(info.pbi_start_tvusec)"
        let fullCommand = command ?? run("/bin/ps", ["-ww", "-p", String(pid), "-o", "command="])?.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let fullCommand, !fullCommand.isEmpty else { return nil }
        var paths = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &paths, size) == size else { return nil }
        let directory = withUnsafePointer(to: &paths.pvi_cdir.vip_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
        guard !directory.isEmpty, birthToken(pid) == token else { return nil }
        let start = Date(timeIntervalSince1970: Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000)
        return ManagedProcessIdentity(pid: pid, parentPID: Int32(info.pbi_ppid), command: fullCommand,
            startedAt: ISO8601DateFormatter().string(from: start), workDir: normalized(directory), processStartToken: token)
    }

    private func exactIdentityStillAlive(_ expected: ManagedProcessIdentity) -> Bool {
        guard let current = identity(expected.pid) else { return false }
        return current.processStartToken == expected.processStartToken && current.command == expected.command
            && current.workDir == expected.workDir
    }

    private func processTable() -> [Int32: String] {
        guard let output = run("/bin/ps", ["-ww", "-axo", "pid=,command="]), output.status == 0 else { return [:] }
        var table: [Int32: String] = [:]
        for line in output.text.split(separator: "\n") {
            let fields = line.split(maxSplits: 1, omittingEmptySubsequences: true, whereSeparator: { $0 == " " || $0 == "\t" })
            if fields.count == 2, let pid = Int32(fields[0]) {
                table[pid] = String(fields[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return table
    }

    private func ownAncestors() -> Set<Int32> {
        var result = Set<Int32>()
        var pid = getpid()
        while pid > 1 && result.insert(pid).inserted {
            guard let info = processInfo(pid) else { break }
            pid = Int32(info.pbi_ppid)
        }
        return result
    }

    private func depth(_ pid: Int32, table: [Int32: String]) -> Int {
        var current = pid
        var visited = Set<Int32>()
        while table[current] != nil && visited.insert(current).inserted {
            guard let info = processInfo(current) else { break }
            current = Int32(info.pbi_ppid)
        }
        return visited.count
    }

    private func waitForExit(_ identities: [ManagedProcessIdentity], timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline && identities.contains(where: { birthToken($0.pid) == $0.processStartToken }) {
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    private func listenerPIDs(_ port: Int) -> Set<Int32>? {
        guard let output = run("/usr/sbin/lsof", ["-nP", "-a", "-iTCP:\(port)", "-sTCP:LISTEN", "-t"]),
              output.status == 0 || output.status == 1 else { return nil }
        return Set(output.text.split(whereSeparator: \.isWhitespace).compactMap { Int32($0) })
    }

    private func portNumber(_ service: ManagedService) -> Int? {
        guard let value = service.healthURL, let url = URL(string: value),
              let host = url.host, ["127.0.0.1", "localhost", "::1", "[::1]"].contains(host) else { return nil }
        return url.port ?? (url.scheme == "https" ? 443 : 80)
    }

    private func normalized(_ path: String) -> String {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            .standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func isWithin(_ path: String, root: String) -> Bool {
        let directory = normalized(path), project = normalized(root)
        return directory == project || directory.hasPrefix(project + "/")
    }

    private func recordURL(_ id: String) -> URL {
        runtimeRoot.appendingPathComponent("pids", isDirectory: true).appendingPathComponent(id + ".json")
    }

    private var leaseDirectory: URL { runtimeRoot.appendingPathComponent("leases", isDirectory: true) }

    private func leaseURL(_ ownerID: String) -> URL {
        let filename = ownerID.utf8.map { String(format: "%02x", $0) }.joined()
        return leaseDirectory.appendingPathComponent(filename + ".json")
    }

    private func readRecord(_ id: String) -> Record? {
        guard let data = try? Data(contentsOf: recordURL(id)) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    private func writeRecord(_ service: ManagedService, primary: ManagedProcessIdentity,
                             identities: [ManagedProcessIdentity]) -> Bool {
        let record = Record(id: service.id, pid: primary.pid, signature: service.processSignature,
            startedAt: primary.startedAt, fullCommand: primary.command, processStartToken: primary.processStartToken,
            workDir: primary.workDir, identities: identities)
        do {
            try fileManager.createDirectory(at: recordURL(service.id).deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(record).write(to: recordURL(service.id), options: .atomic)
            return true
        } catch { return false }
    }

    private func run(_ executable: String, _ arguments: [String]) -> (text: String, status: Int32)? {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "en_US.UTF-8"
        process.environment = environment
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            // Drain before waiting: the system-wide ps result can fill a pipe.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (String(data: data, encoding: .utf8) ?? "", process.terminationStatus)
        } catch { return nil }
    }
}
