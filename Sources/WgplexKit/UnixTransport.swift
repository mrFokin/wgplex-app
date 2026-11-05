import Foundation

/// Byte transport to the daemon over its unix socket (Network.framework).
public final class UnixTransport: Sendable {
    let path: String

    /// A transport to the socket at `path`.
    public init(path: String) {
        self.path = path
    }

    /// One connection per call: sends `request`, reads the reply until EOF.
    /// Throws `RPCError.unavailable` for a missing/unanswered socket, a
    /// timeout and a path of 104 bytes or more (never traps).
    public func roundTrip(_ request: Data, timeout: TimeInterval) async throws -> Data {
        fatalError("not implemented")
    }
}
