import Foundation
import Darwin

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw TestFailure(description: message) }
}

/// Every listener belongs to a child started here, on a random high port, in a
/// fresh temporary directory. Never query or stop the user's application ports.
private final class Fixture {
    let root: URL
    let owned: URL
    let unrelated: URL
    let runtimeRoot: URL
    let runtime: ManagedProcessRuntime
    private var children: [Process] = []

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("managed-runtime-tests-" + UUID().uuidString, isDirectory: true)
        owned = root.appendingPathComponent("owned", isDirectory: true)
        unrelated = root.appendingPathComponent("unrelated", isDirectory: true)
        runtimeRoot = root.appendingPathComponent("runtime", isDirectory: true)
        runtime = ManagedProcessRuntime(runtimeRoot: runtimeRoot)
        for path in [owned, unrelated, runtimeRoot] {
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        }
    }

    func cleanup() {
        for child in children where child.isRunning {
            // Process instances only refer to this test's direct children.
            child.terminate()
            let deadline = Date().addingTimeInterval(2)
            while child.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
            if child.isRunning { _ = Darwin.kill(child.processIdentifier, SIGKILL) }
            child.waitUntilExit()
        }
        try? FileManager.default.removeItem(at: root)
    }

    func unusedPort() throws -> Int {
        for _ in 0..<100 {
            let port = Int.random(in: 49152...65535)
            let descriptor = socket(AF_INET, SOCK_STREAM, 0)
            guard descriptor >= 0 else { throw TestFailure(description: "socket failed") }
            var address = loopback(port)
            let status = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            Darwin.close(descriptor)
            if status == 0 { return port }
        }
        throw TestFailure(description: "could not reserve a random high test port")
    }

    func startHTTP(in directory: URL) throws -> (process: Process, port: Int) {
        // Retry if another local process takes the reservation before Python.
        for _ in 0..<5 {
            let port = try unusedPort()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = ["-u", "-m", "http.server", String(port), "--bind", "127.0.0.1"]
            process.currentDirectoryURL = directory
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            children.append(process)
            let deadline = Date().addingTimeInterval(10)
            while process.isRunning && Date() < deadline {
                if listening(port) {
                    Thread.sleep(forTimeInterval: 0.1)
                    if process.isRunning { return (process, port) }
                }
                Thread.sleep(forTimeInterval: 0.03)
            }
            if process.isRunning { process.terminate(); process.waitUntilExit() }
        }
        throw TestFailure(description: "test Python HTTP server did not start")
    }

    func service(_ id: String, port: Int, signature: String = "http.server") -> ManagedService {
        ManagedService(id: id, workDir: owned.path, processSignature: signature,
                       healthURL: "http://127.0.0.1:\(port)/")
    }

    func record(_ id: String) -> URL {
        runtimeRoot.appendingPathComponent("pids").appendingPathComponent(id + ".json")
    }

    func listening(_ port: Int) -> Bool {
        precondition((49152...65535).contains(port), "Tests must only access their own high ports")
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { Darwin.close(descriptor) }
        var address = loopback(port)
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }

    private func loopback(_ port: Int) -> sockaddr_in {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(port).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        return address
    }
}

@main
private struct ManagedProcessRuntimeTests {
    static func main() {
        let tests: [(String, (Fixture) throws -> Void)] = [
            ("adopt_without_pid_record_and_release_port", adoptWithoutRecord),
            ("rediscover_after_record_deletion", rediscoverAfterDeletion),
            ("preserve_same_signature_from_other_directory", preserveUnrelatedListener),
            ("stop_all_recovers_registered_port_inside_project", recoverProjectListener),
            ("shared_lease_survives_until_last_owner_closes", sharedLeases),
            ("stale_pid_record_cannot_authorize_unrelated_process", stalePIDRecord),
            ("rebuilt_application_requires_fresh_launch", rebuiltApplicationRequiresFreshLaunch),
        ]
        var failures = 0
        for (name, test) in tests {
            do {
                let fixture = try Fixture()
                defer { fixture.cleanup() }
                try test(fixture)
                print("PASS \(name)")
            } catch {
                failures += 1
                print("FAIL \(name): \(error)")
            }
        }
        print("ManagedProcessRuntime: \(tests.count - failures)/\(tests.count) passed")
        exit(failures == 0 ? 0 : 1)
    }

    private static func adoptWithoutRecord(_ fixture: Fixture) throws {
        let child = try fixture.startHTTP(in: fixture.owned)
        let service = fixture.service("adopt", port: child.port)
        try require(!FileManager.default.fileExists(atPath: fixture.record(service.id).path), "unexpected initial record")
        try require(fixture.runtime.adopt(service), "listener without a PID record was not adopted")
        try require(FileManager.default.fileExists(atPath: fixture.record(service.id).path), "adoption did not save its identity")
        try require(fixture.runtime.discover(service).contains { $0.pid == child.process.processIdentifier }, "adoption did not identify the child")
        let result = fixture.runtime.stop([service])
        try require(result.stopped >= 1 && result.remaining == 0 && result.errors.isEmpty, "stop failed: \(result)")
        try require(!fixture.listening(child.port), "owned listener remained open")
        try require(!fixture.runtime.isRunning(service), "stopped service still reports running")
        try require(!FileManager.default.fileExists(atPath: fixture.record(service.id).path), "stopped record was not removed")
    }

    private static func rediscoverAfterDeletion(_ fixture: Fixture) throws {
        let child = try fixture.startHTTP(in: fixture.owned)
        let service = fixture.service("lost-record", port: child.port)
        try require(fixture.runtime.adopt(service, preferredPID: child.process.processIdentifier), "initial adoption failed")
        try FileManager.default.removeItem(at: fixture.record(service.id))
        try require(fixture.runtime.isRunning(service), "record loss hid the live process")
        let result = fixture.runtime.stop([service])
        try require(result.stopped >= 1 && result.remaining == 0, "record loss prevented shutdown: \(result)")
        try require(!fixture.listening(child.port), "rediscovered listener remained open")
    }

    private static func preserveUnrelatedListener(_ fixture: Fixture) throws {
        let child = try fixture.startHTTP(in: fixture.unrelated)
        let service = fixture.service("wrong-cwd", port: child.port)
        try require(fixture.runtime.discover(service, recordedPID: child.process.processIdentifier).isEmpty,
                    "matching signature in another project was trusted")
        try require(!fixture.runtime.adopt(service, preferredPID: child.process.processIdentifier), "unrelated listener was adopted")
        let result = fixture.runtime.stop([service])
        try require(child.process.isRunning && fixture.listening(child.port), "unrelated listener was stopped")
        try require(result.stopped == 0 && result.remaining > 0, "unresolved foreign listener was reported as stopped")
        try require(result.remainingPorts.contains(child.port) && !result.errors.isEmpty, "foreign port conflict was not reported")
    }

    private static func recoverProjectListener(_ fixture: Fixture) throws {
        let child = try fixture.startHTTP(in: fixture.owned)
        let service = fixture.service(
            "orphaned-wrapper",
            port: child.port,
            signature: "wrapper-that-already-exited-" + UUID().uuidString
        )
        let conservative = fixture.runtime.stop([service])
        try require(child.process.isRunning && fixture.listening(child.port),
                    "normal stop must not bypass the configured process signature")
        try require(conservative.remaining > 0 && conservative.remainingPorts.contains(child.port),
                    "normal stop did not report the unresolved registered port")

        let recovered = fixture.runtime.stop([service], recoverProjectListeners: true)
        try require(recovered.stopped >= 1 && recovered.remaining == 0 && recovered.errors.isEmpty,
                    "stop-all recovery failed: \(recovered)")
        try require(!fixture.listening(child.port),
                    "registered project listener remained after stop-all recovery")
    }

    private static func sharedLeases(_ fixture: Fixture) throws {
        let child = try fixture.startHTTP(in: fixture.owned)
        let service = fixture.service("shared", port: child.port)
        try require(fixture.runtime.adopt(service), "shared service adoption failed")
        try require(fixture.runtime.acquireLease(ownerID: "mobile", serviceIDs: [service.id]), "mobile lease failed")
        try require(fixture.runtime.acquireLease(ownerID: "twin", serviceIDs: [service.id]), "twin lease failed")
        fixture.runtime.releaseLease(ownerID: "mobile")
        let retained = fixture.runtime.stop([service], protectedServiceIDs: fixture.runtime.leasedServiceIDs())
        try require(retained.stopped == 0 && retained.remaining == 0 && retained.protectedServiceIDs == [service.id], "shared service protection failed")
        try require(child.process.isRunning && fixture.listening(child.port), "closing the first owner stopped the shared service")
        fixture.runtime.releaseLease(ownerID: "twin")
        try require(fixture.runtime.leasedServiceIDs().isEmpty, "last lease was not released")
        let stopped = fixture.runtime.stop([service], protectedServiceIDs: fixture.runtime.leasedServiceIDs())
        try require(stopped.stopped >= 1 && stopped.remaining == 0, "last owner could not stop the shared service")
        try require(!fixture.listening(child.port), "shared port remained after the last owner closed")
    }

    private static func rebuiltApplicationRequiresFreshLaunch(_ fixture: Fixture) throws {
        let processStart = Date(timeIntervalSince1970: 1_000)
        try require(
            requiresFreshApplicationLaunch(
                launchDate: processStart,
                executableModifiedAt: processStart.addingTimeInterval(2)
            ),
            "a process started before the installed executable changed was reused"
        )
        try require(
            !requiresFreshApplicationLaunch(
                launchDate: processStart,
                executableModifiedAt: processStart.addingTimeInterval(0.2)
            ),
            "filesystem timestamp jitter incorrectly forced a relaunch"
        )
        try require(
            requiresFreshApplicationLaunch(
                launchDate: nil,
                executableModifiedAt: processStart
            ),
            "an unverifiable running process was trusted after a rebuild"
        )
    }

    private static func stalePIDRecord(_ fixture: Fixture) throws {
        let child = try fixture.startHTTP(in: fixture.owned)
        let actual = fixture.service("actual-child", port: child.port)
        let identity = try fixture.runtime.discover(actual).first.unwrap("test child identity was not found")
        // Simulate PID reuse: a saved record names a live PID, but belongs to a
        // different process incarnation and signature. A stale descendant
        // identity must not bypass either check.
        let service = fixture.service("stale", port: try fixture.unusedPort(),
                                      signature: "never-executed-" + UUID().uuidString)
        let staleIdentity: [String: Any] = [
            "pid": identity.pid, "parentPID": identity.parentPID,
            "command": identity.command, "startedAt": identity.startedAt,
            "workDir": identity.workDir, "processStartToken": "1.0",
        ]
        let record: [String: Any] = [
            "id": service.id, "pid": identity.pid, "signature": service.processSignature,
            "startedAt": "1970-01-01T00:00:01Z", "fullCommand": identity.command,
            "processStartToken": "1.0", "workDir": identity.workDir,
            "identities": [staleIdentity],
        ]
        try FileManager.default.createDirectory(at: fixture.record(service.id).deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: record).write(to: fixture.record(service.id))
        try require(fixture.runtime.discover(service).isEmpty, "stale process identity was trusted")
        let result = fixture.runtime.stop([service])
        try require(result.stopped == 0 && result.remaining == 0, "stale PID was selected for shutdown")
        try require(child.process.isRunning && fixture.listening(child.port), "stale PID record killed an unrelated process")
    }
}

private extension Optional {
    func unwrap(_ message: String) throws -> Wrapped {
        guard let value = self else { throw TestFailure(description: message) }
        return value
    }
}
