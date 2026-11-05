import Foundation

/// The minimum `api_version` this app needs.
public let minAPIVersion = 1

/// What the app knows about the engine (design 3).
public enum EngineState: Equatable, Sendable {
    /// `<prefix>/opt/wgplex/bin/wgplex` does not exist for any prefix.
    case notInstalled
    /// The binary exists, but the socket is missing or `status.get` failed.
    case notRunning
    /// The daemon answers, but its `api_version` is below `minAPIVersion`.
    case outdated(apiVersion: Int)
    case ready(Status)
}

public enum Engine {
    /// Homebrew prefixes, Apple Silicon first.
    public static let prefixes = ["/opt/homebrew", "/usr/local"]

    /// `<prefix>/var/run/wgplex.sock`.
    public static func socketPath(prefix: String) -> String { prefix + "/var/run/wgplex.sock" }

    /// `<prefix>/opt/wgplex/bin/wgplex`.
    public static func binaryPath(prefix: String) -> String { prefix + "/opt/wgplex/bin/wgplex" }

    /// Finds the engine and its state. No file system or network access of
    /// its own: `fileExists` and `status` are injected.
    ///
    /// - Parameters:
    ///   - socketOverride: when set, only this socket path is tried and the
    ///     binary check is skipped.
    ///   - fileExists: tells whether a path exists.
    ///   - status: calls `status.get` on the socket at the given path.
    /// - Returns: `notInstalled` when no prefix has the binary; `notRunning`
    ///   when the binary exists but the socket is missing or `status` throws;
    ///   `outdated` for a low `api_version`; otherwise `ready`.
    public static func locate(
        prefixes: [String] = Engine.prefixes,
        socketOverride: String? = nil,
        fileExists: @Sendable (String) -> Bool,
        status: @Sendable (String) async throws -> Status
    ) async -> EngineState {
        func state(of s: Status) -> EngineState {
            s.apiVersion < minAPIVersion ? .outdated(apiVersion: s.apiVersion) : .ready(s)
        }

        if let socketOverride {
            guard let s = try? await status(socketOverride) else {
                return .notRunning
            }
            return state(of: s)
        }

        let installed = prefixes.filter { fileExists(binaryPath(prefix: $0)) }
        if installed.isEmpty {
            return .notInstalled
        }
        for prefix in installed {
            let socket = socketPath(prefix: prefix)
            if fileExists(socket), let s = try? await status(socket) {
                return state(of: s)
            }
        }
        return .notRunning
    }
}
