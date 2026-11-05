import Foundation

/// Errors of a call to the daemon.
public enum RPCError: Error, Equatable, Sendable {
    /// No socket, nobody answers, or a timeout.
    case unavailable(String)
    /// Not a valid HTTP/JSON-RPC exchange: bad HTTP status (413, 415, ...),
    /// malformed reply.
    case transport(String)
    /// A JSON-RPC error object of the daemon.
    case server(code: Int, message: String, data: Data?)

    /// Error 1 (`config.reload`): the config is invalid; the previous keeps running.
    public static let configInvalidCode = 1
    /// Error 2: no config applied.
    public static let notConfiguredCode = 2
    /// Error 3: unknown tunnel.
    public static let unknownTunnelCode = 3
    /// Error 4: the tunnel failed to start (its toggle stays on).
    public static let tunnelStartFailedCode = 4
    /// Error 5: the caller cannot control.
    public static let permissionDeniedCode = 5

    /// Typed view of a `.server` error; `nil` for `.unavailable`/`.transport`.
    public var kind: Kind? {
        guard case .server(let code, _, let data) = self else {
            return nil
        }
        switch code {
        case Self.configInvalidCode:
            let d = data.flatMap { try? JSONDecoder().decode(ConfigErrorData.self, from: $0) }
            return .configInvalid(errors: d?.errors ?? [], warnings: d?.warnings ?? [])
        case Self.notConfiguredCode: return .notConfigured
        case Self.unknownTunnelCode: return .unknownTunnel
        case Self.tunnelStartFailedCode: return .tunnelStartFailed
        case Self.permissionDeniedCode:
            let d = data.flatMap { try? JSONDecoder().decode(PermissionData.self, from: $0) }
            return .permissionDenied(controlGroup: d?.controlGroup ?? "")
        case -32700: return .parseError
        case -32600: return .invalidRequest
        case -32601: return .methodNotFound
        case -32602: return .invalidParams
        case -32603: return .internalError
        default: return .other(code: code)
        }
    }

    private struct ConfigErrorData: Decodable {
        var errors: [String]?
        var warnings: [String]?
    }

    private struct PermissionData: Decodable {
        var controlGroup: String?

        enum CodingKeys: String, CodingKey {
            case controlGroup = "control_group"
        }
    }

    public enum Kind: Equatable, Sendable {
        case configInvalid(errors: [String], warnings: [String])
        case notConfigured
        case unknownTunnel
        case tunnelStartFailed
        /// `controlGroup` is "" when the config has none.
        case permissionDenied(controlGroup: String)
        /// -32700
        case parseError
        /// -32600
        case invalidRequest
        /// -32601
        case methodNotFound
        /// -32602
        case invalidParams
        /// -32603
        case internalError
        /// Any other code.
        case other(code: Int)
    }
}

extension RPCError: LocalizedError {
    /// English text for the UI; for `permissionDenied` it names the control group.
    public var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            return "The wgplex daemon is unavailable: \(reason)"
        case .transport(let reason):
            return "Bad reply from the wgplex daemon: \(reason)"
        case .server(_, let message, _):
            if case .permissionDenied(let group) = kind {
                return "Permission denied: requires root, the config owner"
                    + (group.isEmpty ? "" : " or membership in group \"\(group)\"")
            }
            return message
        }
    }
}
