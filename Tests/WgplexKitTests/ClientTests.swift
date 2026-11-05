import XCTest

@testable import WgplexKit

/// Client over a `roundTrip` closure (no socket): request shape, results,
/// error mapping (docs/api.md "Transport", "Errors").
final class ClientTests: XCTestCase {
    /// A client answering every request with `reply(method)`; requests are recorded.
    private func harness(_ reply: @escaping @Sendable (String) -> FakeReply) -> (Client, Recorder) {
        let rec = Recorder()
        let client = Client(roundTrip: { request, _ in
            rec.add(request)
            return httpResponse(for: reply(rpcMethod(of: request) ?? ""), request: request)
        })
        return (client, rec)
    }

    private func rpcError(_ body: () async throws -> some Any, file: StaticString = #filePath, line: UInt = #line)
        async -> RPCError?
    {
        do {
            _ = try await body()
            XCTFail("expected an error", file: file, line: line)
        } catch let e as RPCError {
            return e
        } catch {
            XCTFail("expected RPCError, got \(error)", file: file, line: line)
        }
        return nil
    }

    private func params(_ request: Data) -> [String: Any]? { rpcBody(of: request)?["params"] as? [String: Any] }

    // MARK: Request shape

    func testRequestIsPostRPCJSON() async throws {
        let (c, rec) = harness { _ in .result(Fixture.statusFull) }
        _ = try await c.status()
        let req = try XCTUnwrap(rec.requests.first)
        let (head, _) = try XCTUnwrap(splitHTTP(req))
        XCTAssertTrue(head.hasPrefix("POST /rpc HTTP/1.1"), head)
        XCTAssertTrue(head.lowercased().contains("content-type: application/json"), head)
        let body = try XCTUnwrap(rpcBody(of: req))
        XCTAssertEqual(body["jsonrpc"] as? String, "2.0")
        XCTAssertNotNil(body["id"], "a request without id is a notification: no reply")
        XCTAssertEqual(body["method"] as? String, "status.get")
    }

    // api: Methods table. Method names and params.
    func testMethodNamesAndParams() async throws {
        let (c, rec) = harness { method in
            switch method {
            case "status.get": return .result(Fixture.statusFull)
            case "diag.explain": return .result(Fixture.explainDomain)
            case "diag.routes": return .result(Fixture.routes)
            case "config.reload": return .result(Fixture.applyResult)
            case "tunnel.enable": return .result("{}")
            default: return .result("null")
            }
        }
        _ = try await c.status()
        _ = try await c.explain("Example.com")
        _ = try await c.routes()
        _ = try await c.reload()
        _ = try await c.enable("work")
        try await c.disable("work")
        try await c.disableAll()
        try await c.pause()
        try await c.resume()
        XCTAssertEqual(
            rec.methods,
            [
                "status.get", "diag.explain", "diag.routes", "config.reload", "tunnel.enable", "tunnel.disable",
                "tunnel.disableAll", "daemon.pause", "daemon.resume",
            ])
        let reqs = rec.requests
        XCTAssertEqual(params(reqs[1])?["query"] as? String, "Example.com")
        XCTAssertEqual(params(reqs[4]) as? [String: String], ["name": "work"])
        XCTAssertEqual(params(reqs[5]) as? [String: String], ["name": "work"])
        // Methods without params: omitted or an empty object, never null or a scalar.
        for i in [0, 2, 3, 6, 7, 8] {
            let raw = rpcBody(of: reqs[i])?["params"]
            XCTAssertTrue(raw == nil || (raw as? [String: Any])?.isEmpty == true, "method \(rec.methods[i])")
        }
    }

    // MARK: Results

    func testResults() async throws {
        let (c, _) = harness { method in
            switch method {
            case "status.get": return .result(Fixture.statusPaused)
            case "diag.explain": return .result(Fixture.explainIP)
            case "diag.routes": return .result(Fixture.routes)
            case "config.reload": return .result(Fixture.applyResult)
            default: return .result("{}")
            }
        }
        let s = try await c.status()
        XCTAssertTrue(s.paused)
        let e = try await c.explain("93.184.216.34")
        XCTAssertEqual(e.kind, .ip)
        let r = try await c.routes()
        XCTAssertEqual(r.routes.count, 4)
        let a = try await c.reload()
        XCTAssertEqual(a.tunnels.map(\.name), ["home"])
        let en = try await c.enable("work")
        XCTAssertFalse(en.startsOnResume)
    }

    // api: tunnel.enable on pause -> starts_on_resume.
    func testEnableOnPauseStartsOnResume() async throws {
        let (c, _) = harness { _ in .result(#"{"starts_on_resume": true}"#) }
        let r = try await c.enable("work")
        XCTAssertTrue(r.startsOnResume)
    }

    // api: result `null` for disable, disableAll, pause, resume.
    func testNullResultsAreSuccess() async throws {
        let (c, _) = harness { _ in .result("null") }
        try await c.disable("t")
        try await c.disableAll()
        try await c.pause()
        try await c.resume()
    }

    // MARK: HTTP framing

    func testResponseWithoutContentLengthReadsToEOF() async throws {
        let (c, _) = harness { _ in .resultUntilEOF(Fixture.statusFull) }
        let s = try await c.status()
        XCTAssertEqual(s.version, "0.1.0-dev")
    }

    // plan A1 decision 2: HTTP 413/415 and foreign statuses are transport errors.
    func testNon200IsTransport() async {
        for status in [404, 405, 413, 415, 500] {
            let (c, _) = harness { _ in .http(status: status, body: "nope") }
            let e = await rpcError { try await c.status() }
            guard case .transport? = e else { XCTFail("HTTP \(status): \(String(describing: e))"); continue }
            XCTAssertNil(e?.kind)
        }
    }

    func testMalformedBodyIsTransport() async {
        let (c, _) = harness { _ in .http(status: 200, body: "<html>not json</html>") }
        let e = await rpcError { try await c.status() }
        guard case .transport? = e else { return XCTFail(String(describing: e)) }
    }

    func testGarbageInsteadOfHTTPIsTransport() async {
        let c = Client(roundTrip: { _, _ in Data("garbage".utf8) })
        let e = await rpcError { try await c.status() }
        guard case .transport? = e else { return XCTFail(String(describing: e)) }
    }

    func testRoundTripUnavailablePropagates() async {
        let c = Client(roundTrip: { _, _ in throw RPCError.unavailable("no socket") })
        let e = await rpcError { try await c.status() }
        XCTAssertEqual(e, .unavailable("no socket"))
        XCTAssertNil(e?.kind)
    }

    // MARK: Errors 1-5 and -327xx

    // api: Errors, code 1 with ConfigErrorData.
    func testError1ConfigInvalid() async {
        let (c, _) = harness { _ in
            .error(code: 1, message: "invalid config", data: #"{"errors": ["e1", "e2"], "warnings": ["w1"]}"#)
        }
        let e = await rpcError { try await c.reload() }
        XCTAssertEqual(e?.kind, .configInvalid(errors: ["e1", "e2"], warnings: ["w1"]))
        guard case .server(let code, let msg, let data)? = e else { return XCTFail() }
        XCTAssertEqual(code, RPCError.configInvalidCode)
        XCTAssertEqual(msg, "invalid config")
        XCTAssertNotNil(data)
    }

    func testError1WithoutData() async {
        let (c, _) = harness { _ in .error(code: 1) }
        let e = await rpcError { try await c.reload() }
        XCTAssertEqual(e?.kind, .configInvalid(errors: [], warnings: []))
    }

    func testErrors2To4() async {
        let (c2, _) = harness { _ in .error(code: 2) }
        let e2 = await rpcError { try await c2.enable("t") }
        XCTAssertEqual(e2?.kind, .notConfigured)
        let e2b = await rpcError { try await c2.disableAll() }
        XCTAssertEqual(e2b?.kind, .notConfigured)

        let (c3, _) = harness { _ in .error(code: 3) }
        let e3 = await rpcError { try await c3.disable("nope") }
        XCTAssertEqual(e3?.kind, .unknownTunnel)

        let (c4, _) = harness { _ in .error(code: 4) }
        let e4 = await rpcError { try await c4.enable("t") }
        XCTAssertEqual(e4?.kind, .tunnelStartFailed)
    }

    // api: error 5 with PermissionData.
    func testError5PermissionDenied() async {
        let (c, _) = harness { _ in .error(code: 5, data: #"{"control_group": "admin"}"#) }
        let e = await rpcError { try await c.pause() }
        XCTAssertEqual(e?.kind, .permissionDenied(controlGroup: "admin"))
        XCTAssertTrue(e?.errorDescription?.contains("admin") == true, e?.errorDescription ?? "nil")
    }

    func testError5WithEmptyOrMissingGroup() async {
        let (c, _) = harness { _ in .error(code: 5, data: #"{"control_group": ""}"#) }
        let e = await rpcError { try await c.resume() }
        XCTAssertEqual(e?.kind, .permissionDenied(controlGroup: ""))
        XCTAssertNotNil(e?.errorDescription)

        let (c2, _) = harness { _ in .error(code: 5) }
        let e2 = await rpcError { try await c2.reload() }
        XCTAssertEqual(e2?.kind, .permissionDenied(controlGroup: ""))
    }

    func testStandardErrorCodes() async {
        let table: [(Int, RPCError.Kind)] = [
            (-32700, .parseError), (-32600, .invalidRequest), (-32601, .methodNotFound),
            (-32602, .invalidParams), (-32603, .internalError), (42, .other(code: 42)),
            (-32000, .other(code: -32000)),
        ]
        for (code, kind) in table {
            let (c, _) = harness { _ in .error(code: code) }
            let e = await rpcError { try await c.status() }
            XCTAssertEqual(e?.kind, kind, "code \(code)")
        }
    }

    func testInvalidParamsOnEmptyName() async {
        let (c, rec) = harness { _ in .error(code: -32602, message: "empty name") }
        let e = await rpcError { try await c.enable("") }
        XCTAssertEqual(e?.kind, .invalidParams)
        XCTAssertEqual(rec.methods, ["tunnel.enable"], "the daemon validates, the client sends as is")
    }

    func testErrorCodeConstants() {
        XCTAssertEqual(RPCError.configInvalidCode, 1)
        XCTAssertEqual(RPCError.notConfiguredCode, 2)
        XCTAssertEqual(RPCError.unknownTunnelCode, 3)
        XCTAssertEqual(RPCError.tunnelStartFailedCode, 4)
        XCTAssertEqual(RPCError.permissionDeniedCode, 5)
    }

    func testKindIsNilForNonServerErrors() {
        XCTAssertNil(RPCError.unavailable("x").kind)
        XCTAssertNil(RPCError.transport("x").kind)
    }

    func testDescriptionsExist() {
        XCTAssertFalse((RPCError.unavailable("no socket").errorDescription ?? "").isEmpty)
        XCTAssertFalse((RPCError.transport("bad").errorDescription ?? "").isEmpty)
        XCTAssertFalse((RPCError.server(code: 3, message: "unknown tunnel", data: nil).errorDescription ?? "").isEmpty)
    }

    // MARK: End to end over a real unix socket

    func testClientOverFakeServer() async throws {
        let server = try FakeAPIServer { method in
            switch method {
            case "status.get": return .result(Fixture.statusFull)
            case "tunnel.enable": return .result(#"{"starts_on_resume": true}"#)
            case "daemon.pause": return .error(code: 5, data: #"{"control_group": "staff"}"#)
            default: return .error(code: -32601)
            }
        }
        defer { server.stop() }
        let c = Client(path: server.path)
        let s = try await c.status()
        XCTAssertEqual(s.tunnels.count, 2)
        let en = try await c.enable("work")
        XCTAssertTrue(en.startsOnResume)
        let e = await rpcError { try await c.pause() }
        XCTAssertEqual(e?.kind, .permissionDenied(controlGroup: "staff"))
        XCTAssertEqual(server.methods, ["status.get", "tunnel.enable", "daemon.pause"])
        let enableBody = try XCTUnwrap(rpcBody(of: server.requests[1]))
        XCTAssertEqual((enableBody["params"] as? [String: Any])?["name"] as? String, "work")
    }

    func testClientOverMissingSocketIsUnavailable() async {
        let c = Client(path: "/tmp/wgx-does-not-exist-\(UUID().uuidString.prefix(6)).sock")
        let e = await rpcError { try await c.status() }
        guard case .unavailable? = e else { return XCTFail(String(describing: e)) }
    }
}
