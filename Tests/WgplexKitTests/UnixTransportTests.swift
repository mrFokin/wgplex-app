import XCTest

@testable import WgplexKit

/// UnixTransport against a fake daemon on a real unix socket.
final class UnixTransportTests: XCTestCase {
    private func request(_ method: String = "status.get") -> Data {
        let body = #"{"jsonrpc":"2.0","id":1,"method":"\#(method)"}"#
        let head =
            "POST /rpc HTTP/1.1\r\nHost: wgplex\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n"
        return Data((head + body).utf8)
    }

    private func expectUnavailable(_ body: () async throws -> Data, file: StaticString = #filePath, line: UInt = #line)
        async
    {
        do {
            _ = try await body()
            XCTFail("expected RPCError.unavailable", file: file, line: line)
        } catch let e as RPCError {
            guard case .unavailable = e else { return XCTFail("\(e)", file: file, line: line) }
        } catch {
            XCTFail("expected RPCError, got \(error)", file: file, line: line)
        }
    }

    func testRoundTripReturnsFullHTTPResponse() async throws {
        let server = try FakeAPIServer { _ in .result(#"{"ok":true}"#) }
        defer { server.stop() }
        let t = UnixTransport(path: server.path)
        let data = try await t.roundTrip(request(), timeout: 5)
        let (head, body) = try XCTUnwrap(splitHTTP(data))
        XCTAssertTrue(head.hasPrefix("HTTP/1.1 200"), head)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual((json["result"] as? [String: Any])?["ok"] as? Bool, true)
        XCTAssertEqual(server.requests.count, 1)
        XCTAssertEqual(server.requests.first, request(), "the request arrives byte for byte")
    }

    // plan A1 decision 1: one connection per call, several calls in a row.
    func testSeveralCallsOneConnectionEach() async throws {
        let server = try FakeAPIServer { _ in .result("{}") }
        defer { server.stop() }
        let t = UnixTransport(path: server.path)
        for method in ["status.get", "diag.routes", "daemon.pause"] {
            _ = try await t.roundTrip(request(method), timeout: 5)
        }
        XCTAssertEqual(server.methods, ["status.get", "diag.routes", "daemon.pause"])
    }

    func testResponseWithoutContentLengthReadsToEOF() async throws {
        let server = try FakeAPIServer { _ in .resultUntilEOF(#"{"a":"b"}"#) }
        defer { server.stop() }
        let data = try await UnixTransport(path: server.path).roundTrip(request(), timeout: 5)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).hasSuffix(#"{"jsonrpc":"2.0","id":1,"result":{"a":"b"}}"#))
    }

    func testLargeResponse() async throws {
        let big = "[" + (0..<20_000).map { "\"item-\($0)\"" }.joined(separator: ",") + "]"
        let server = try FakeAPIServer { _ in .result(big) }
        defer { server.stop() }
        let data = try await UnixTransport(path: server.path).roundTrip(request(), timeout: 10)
        let (_, body) = try XCTUnwrap(splitHTTP(data))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual((json["result"] as? [Any])?.count, 20_000)
    }

    func testMissingSocketIsUnavailable() async {
        let t = UnixTransport(path: "/tmp/wgx-missing-\(UUID().uuidString.prefix(6)).sock")
        await expectUnavailable { try await t.roundTrip(self.request(), timeout: 2) }
    }

    // A socket file nobody listens on (left after a crash).
    func testStaleSocketIsUnavailable() async throws {
        let server = try FakeAPIServer { _ in .result("{}") }
        let path = server.path
        server.stop()
        // stop() removes the file; recreate a plain file at the path.
        FileManager.default.createFile(atPath: path, contents: Data())
        defer { unlink(path) }
        let t = UnixTransport(path: path)
        await expectUnavailable { try await t.roundTrip(self.request(), timeout: 2) }
    }

    func testTimeoutIsUnavailable() async throws {
        let server = try FakeAPIServer { _ in .hang }
        defer { server.stop() }
        let t = UnixTransport(path: server.path)
        let start = Date()
        await expectUnavailable { try await t.roundTrip(self.request(), timeout: 0.3) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 3, "the timeout is honoured")
    }

    // A path of 104 bytes or more does not fit sockaddr_un: an error, never a trap.
    func testTooLongPathIsUnavailable() async {
        for length in [104, 105, 300] {
            let path = "/tmp/" + String(repeating: "a", count: length - 5)
            XCTAssertEqual(path.utf8.count, length)
            let t = UnixTransport(path: path)
            await expectUnavailable { try await t.roundTrip(self.request(), timeout: 2) }
        }
    }

    // The longest path that fits (103 bytes) is tried normally: missing -> unavailable.
    func testBoundaryPathJustFits() async {
        let path = "/tmp/" + String(repeating: "b", count: 98)
        XCTAssertEqual(path.utf8.count, 103)
        let t = UnixTransport(path: path)
        await expectUnavailable { try await t.roundTrip(self.request(), timeout: 2) }
    }

    func testEmptyPathIsUnavailable() async {
        let t = UnixTransport(path: "")
        await expectUnavailable { try await t.roundTrip(self.request(), timeout: 2) }
    }
}
