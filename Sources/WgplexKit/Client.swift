import Foundation

/// The JSON-RPC client of the wgplex daemon (POST /rpc over HTTP/1.1).
/// Every method throws `RPCError`.
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

    /// `status.get`.
    public func status() async throws -> Status { fatalError("not implemented") }

    /// `diag.explain` for a domain or an IP address.
    public func explain(_ query: String) async throws -> Explanation { fatalError("not implemented") }

    /// `diag.routes`.
    public func routes() async throws -> Routes { fatalError("not implemented") }

    /// `config.reload`. Errors 1, 5.
    public func reload() async throws -> ApplyResult { fatalError("not implemented") }

    /// `tunnel.enable`. Errors 2, 3, 4, 5, -32602.
    public func enable(_ name: String) async throws -> EnableResult { fatalError("not implemented") }

    /// `tunnel.disable`. Errors 2, 3, 5, -32602.
    public func disable(_ name: String) async throws { fatalError("not implemented") }

    /// `tunnel.disableAll`. Errors 2, 5.
    public func disableAll() async throws { fatalError("not implemented") }

    /// `daemon.pause`. Error 5.
    public func pause() async throws { fatalError("not implemented") }

    /// `daemon.resume`. Error 5.
    public func resume() async throws { fatalError("not implemented") }
}
