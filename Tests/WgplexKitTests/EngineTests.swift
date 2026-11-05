import XCTest

@testable import WgplexKit

/// Engine lookup and the states of design 3 (installed / running / outdated).
final class EngineTests: XCTestCase {
    private struct Boom: Error {}

    /// Thread-safe log of what locate asked for.
    private final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var _files: [String] = []
        private var _statuses: [String] = []
        func file(_ p: String) { lock.lock(); _files.append(p); lock.unlock() }
        func status(_ p: String) { lock.lock(); _statuses.append(p); lock.unlock() }
        var files: [String] { lock.lock(); defer { lock.unlock() }; return _files }
        var statuses: [String] { lock.lock(); defer { lock.unlock() }; return _statuses }
    }

    private func locate(
        existing: Set<String>, socketOverride: String? = nil, apiVersion: Int = 1, failing: Bool = false,
        calls: Calls = Calls()
    ) async -> EngineState {
        await Engine.locate(
            socketOverride: socketOverride,
            fileExists: { calls.file($0); return existing.contains($0) },
            status: { path in
                calls.status(path)
                if failing { throw RPCError.unavailable("nobody answers") }
                return Status(apiVersion: apiVersion, version: "0.1.0-dev")
            })
    }

    func testPaths() {
        XCTAssertEqual(Engine.prefixes, ["/opt/homebrew", "/usr/local"])
        XCTAssertEqual(Engine.socketPath(prefix: "/opt/homebrew"), "/opt/homebrew/var/run/wgplex.sock")
        XCTAssertEqual(Engine.socketPath(prefix: "/usr/local"), "/usr/local/var/run/wgplex.sock")
        XCTAssertEqual(Engine.binaryPath(prefix: "/opt/homebrew"), "/opt/homebrew/opt/wgplex/bin/wgplex")
        XCTAssertEqual(Engine.binaryPath(prefix: "/usr/local"), "/usr/local/opt/wgplex/bin/wgplex")
        XCTAssertEqual(minAPIVersion, 1)
    }

    // design 3: no binary under any prefix.
    func testNotInstalled() async {
        let state = await locate(existing: [])
        XCTAssertEqual(state, .notInstalled)
    }

    // A socket without a binary does not make the engine installed.
    func testNotInstalledEvenWithSocket() async {
        let state = await locate(existing: [Engine.socketPath(prefix: "/opt/homebrew")])
        XCTAssertEqual(state, .notInstalled)
    }

    // design 3: binary present, no socket.
    func testNotRunningWithoutSocket() async {
        let calls = Calls()
        let state = await locate(existing: [Engine.binaryPath(prefix: "/opt/homebrew")], calls: calls)
        XCTAssertEqual(state, .notRunning)
    }

    // design 3: binary and socket, but status.get fails.
    func testNotRunningWhenStatusFails() async {
        let existing: Set = [Engine.binaryPath(prefix: "/opt/homebrew"), Engine.socketPath(prefix: "/opt/homebrew")]
        let state = await locate(existing: existing, failing: true)
        XCTAssertEqual(state, .notRunning)
    }

    func testOutdated() async {
        let existing: Set = [Engine.binaryPath(prefix: "/opt/homebrew"), Engine.socketPath(prefix: "/opt/homebrew")]
        let state = await locate(existing: existing, apiVersion: 0)
        XCTAssertEqual(state, .outdated(apiVersion: 0))
    }

    func testReady() async {
        let existing: Set = [Engine.binaryPath(prefix: "/opt/homebrew"), Engine.socketPath(prefix: "/opt/homebrew")]
        let state = await locate(existing: existing)
        guard case .ready(let s) = state else { return XCTFail("\(state)") }
        XCTAssertEqual(s.apiVersion, 1)
        XCTAssertEqual(s.version, "0.1.0-dev")
    }

    // A newer api_version than the minimum is fine (fields are only added).
    func testNewerAPIVersionIsReady() async {
        let existing: Set = [Engine.binaryPath(prefix: "/opt/homebrew"), Engine.socketPath(prefix: "/opt/homebrew")]
        let state = await locate(existing: existing, apiVersion: 7)
        guard case .ready(let s) = state else { return XCTFail("\(state)") }
        XCTAssertEqual(s.apiVersion, 7)
    }

    // Intel prefix: Homebrew in /usr/local.
    func testIntelPrefix() async {
        let calls = Calls()
        let existing: Set = [Engine.binaryPath(prefix: "/usr/local"), Engine.socketPath(prefix: "/usr/local")]
        let state = await locate(existing: existing, calls: calls)
        guard case .ready = state else { return XCTFail("\(state)") }
        XCTAssertEqual(calls.statuses, ["/usr/local/var/run/wgplex.sock"])
    }

    // Apple Silicon is tried first when both are installed.
    func testAppleSiliconFirst() async {
        let calls = Calls()
        var existing: Set<String> = []
        for p in Engine.prefixes {
            existing.insert(Engine.binaryPath(prefix: p))
            existing.insert(Engine.socketPath(prefix: p))
        }
        let state = await locate(existing: existing, calls: calls)
        guard case .ready = state else { return XCTFail("\(state)") }
        XCTAssertEqual(calls.statuses.first, "/opt/homebrew/var/run/wgplex.sock")
    }

    func testCustomPrefixes() async {
        let state = await Engine.locate(
            prefixes: ["/tmp/x"],
            fileExists: { $0 == "/tmp/x/opt/wgplex/bin/wgplex" || $0 == "/tmp/x/var/run/wgplex.sock" },
            status: { path in
                XCTAssertEqual(path, "/tmp/x/var/run/wgplex.sock")
                return Status(apiVersion: 1)
            })
        guard case .ready = state else { return XCTFail("\(state)") }
    }

    // socketOverride: only that socket, the binary check is skipped.
    func testSocketOverrideSkipsBinaryCheck() async {
        let calls = Calls()
        let state = await locate(existing: ["/tmp/custom.sock"], socketOverride: "/tmp/custom.sock", calls: calls)
        guard case .ready = state else { return XCTFail("\(state)") }
        XCTAssertEqual(calls.statuses, ["/tmp/custom.sock"])
        XCTAssertFalse(calls.files.contains { $0.hasSuffix("/opt/wgplex/bin/wgplex") }, "binary is not checked")
    }

    func testSocketOverrideIgnoresStandardSockets() async {
        let calls = Calls()
        let existing: Set = [Engine.binaryPath(prefix: "/opt/homebrew"), Engine.socketPath(prefix: "/opt/homebrew")]
        let state = await locate(existing: existing, socketOverride: "/tmp/custom.sock", failing: true, calls: calls)
        XCTAssertEqual(state, .notRunning)
        XCTAssertFalse(calls.statuses.contains(Engine.socketPath(prefix: "/opt/homebrew")))
    }

    func testSocketOverrideOutdated() async {
        let state = await locate(existing: ["/tmp/custom.sock"], socketOverride: "/tmp/custom.sock", apiVersion: 0)
        XCTAssertEqual(state, .outdated(apiVersion: 0))
    }
}
