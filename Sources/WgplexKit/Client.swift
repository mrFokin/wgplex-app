import Foundation

/// The JSON-RPC client of the wgplex daemon (POST /rpc over HTTP/1.1).
/// Every method throws `RPCError` (or `CancellationError` when the task is cancelled).
public final class Client: Sendable {
    let roundTrip: @Sendable (Data, TimeInterval) async throws -> Data

    /// A client over `roundTrip`, which takes a full HTTP request and a
    /// timeout and returns the full HTTP response (tests substitute it).
    public init(roundTrip: @escaping @Sendable (Data, TimeInterval) async throws -> Data) {
        self.roundTrip = roundTrip
    }

    /// A client over a `UnixTransport` to `path`.
    public convenience init(path: String) {
        let transport = UnixTransport(path: path)
        self.init(roundTrip: { try await transport.roundTrip($0, timeout: $1) })
    }

    /// `status.get`, timeout 5 s.
    public func status() async throws -> Status {
        try await call("status.get", timeout: 5)
    }

    /// `diag.explain` for a domain or an IP address, timeout 5 s.
    public func explain(_ query: String) async throws -> Explanation {
        try await call("diag.explain", params: ["query": query], timeout: 5)
    }

    /// `diag.routes`, timeout 5 s.
    public func routes() async throws -> Routes {
        try await call("diag.routes", timeout: 5)
    }

    /// `config.reload`, timeout 30 s. Errors 1, 5.
    public func reload() async throws -> ApplyResult {
        try await call("config.reload", timeout: 30)
    }

    /// `tunnel.enable`, timeout 30 s. Errors 2, 3, 4, 5, -32602.
    public func enable(_ name: String) async throws -> EnableResult {
        try await call("tunnel.enable", params: ["name": name], timeout: 30)
    }

    /// `tunnel.disable`, timeout 30 s. Errors 2, 3, 5, -32602.
    public func disable(_ name: String) async throws {
        let _: Empty = try await call("tunnel.disable", params: ["name": name], timeout: 30)
    }

    /// `tunnel.disableAll`, timeout 30 s. Errors 2, 5.
    public func disableAll() async throws {
        let _: Empty = try await call("tunnel.disableAll", timeout: 30)
    }

    /// `daemon.pause`, timeout 30 s. Error 5.
    public func pause() async throws {
        let _: Empty = try await call("daemon.pause", timeout: 30)
    }

    /// `daemon.resume`, timeout 30 s. Error 5.
    public func resume() async throws {
        let _: Empty = try await call("daemon.resume", timeout: 30)
    }

    /// One JSON-RPC call over HTTP; the reply is decoded by `JSONRPC`.
    private func call<T: Decodable>(
        _ method: String, params: [String: String]? = nil, timeout: TimeInterval
    ) async throws -> T {
        let body = try JSONRPC.encode(method: method, params: params)
        let response = try await roundTrip(HTTP.request(body: body), timeout)
        return try JSONRPC.decode(T.self, from: HTTP.body(of: response))
    }
}
