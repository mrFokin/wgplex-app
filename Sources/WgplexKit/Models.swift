import Foundation

// Reply types of docs/api.md (api_version 1). Fields the daemon omits decode
// to [] for arrays, nil for optionals and false/0 for scalars; unknown fields
// are ignored. Times are RFC 3339, with or without fractional seconds. No
// reply carries a WireGuard key.

/// Result of `status.get`. Fields marked redacted are empty for a caller
/// that cannot control.
public struct Status: Decodable, Equatable, Sendable {
    public var apiVersion: Int
    /// Version of the engine (the daemon binary).
    public var version: String
    /// The caller may call mutating methods and sees full replies.
    public var canControl: Bool
    /// `control_group` of the applied config; "" without one.
    public var controlGroup: String
    /// A config has been applied.
    public var configured: Bool
    /// Not configured, but the block snapshot of the last config is enforced.
    public var blockSnapshot: Bool
    public var paused: Bool
    public var configDir: String
    public var logPath: String
    public var icon: Icon
    /// Redacted.
    public var configErrors: [String]
    public var configErrorCount: Int
    /// Redacted.
    public var warnings: [String]
    public var warningCount: Int
    public var tunnels: [TunnelStatus]
    public var rules: [RuleStatus]

    public init(
        apiVersion: Int = 1, version: String = "", canControl: Bool = false, controlGroup: String = "",
        configured: Bool = false, blockSnapshot: Bool = false, paused: Bool = false,
        configDir: String = "", logPath: String = "", icon: Icon = .off,
        configErrors: [String] = [], configErrorCount: Int = 0,
        warnings: [String] = [], warningCount: Int = 0,
        tunnels: [TunnelStatus] = [], rules: [RuleStatus] = []
    ) {
        self.apiVersion = apiVersion
        self.version = version
        self.canControl = canControl
        self.controlGroup = controlGroup
        self.configured = configured
        self.blockSnapshot = blockSnapshot
        self.paused = paused
        self.configDir = configDir
        self.logPath = logPath
        self.icon = icon
        self.configErrors = configErrors
        self.configErrorCount = configErrorCount
        self.warnings = warnings
        self.warningCount = warningCount
        self.tunnels = tunnels
        self.rules = rules
    }

    enum Keys: String, CodingKey {
        case apiVersion = "api_version"
        case version
        case canControl = "can_control"
        case controlGroup = "control_group"
        case configured
        case blockSnapshot = "block_snapshot"
        case paused
        case configDir = "config_dir"
        case logPath = "log_path"
        case icon
        case configErrors = "config_errors"
        case configErrorCount = "config_error_count"
        case warnings
        case warningCount = "warning_count"
        case tunnels
        case rules
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        apiVersion = try c.decodeIfPresent(Int.self, forKey: .apiVersion) ?? 0
        version = try c.decodeIfPresent(String.self, forKey: .version) ?? ""
        canControl = try c.decodeIfPresent(Bool.self, forKey: .canControl) ?? false
        controlGroup = try c.decodeIfPresent(String.self, forKey: .controlGroup) ?? ""
        configured = try c.decodeIfPresent(Bool.self, forKey: .configured) ?? false
        blockSnapshot = try c.decodeIfPresent(Bool.self, forKey: .blockSnapshot) ?? false
        paused = try c.decodeIfPresent(Bool.self, forKey: .paused) ?? false
        configDir = try c.decodeIfPresent(String.self, forKey: .configDir) ?? ""
        logPath = try c.decodeIfPresent(String.self, forKey: .logPath) ?? ""
        icon = try c.decodeIfPresent(Icon.self, forKey: .icon) ?? .off
        configErrors = try c.decodeIfPresent([String].self, forKey: .configErrors) ?? []
        configErrorCount = try c.decodeIfPresent(Int.self, forKey: .configErrorCount) ?? 0
        warnings = try c.decodeIfPresent([String].self, forKey: .warnings) ?? []
        warningCount = try c.decodeIfPresent(Int.self, forKey: .warningCount) ?? 0
        tunnels = try c.decodeIfPresent([TunnelStatus].self, forKey: .tunnels) ?? []
        rules = try c.decodeIfPresent([RuleStatus].self, forKey: .rules) ?? []
    }
}

/// One tunnel of `Status`.
public struct TunnelStatus: Decodable, Equatable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    /// The toggle (persisted), not "running"; see `state`.
    public var enabled: Bool
    public var state: TunnelState
    /// State `error`: why it failed to start. Redacted.
    public var error: String?
    /// `utunN`, states `up` and `dead`.
    public var interface: String?
    public var addresses: [String]
    public var routes: RouteMode
    public var routeCount: Int
    /// States `up` and `dead`, in `.conf` order.
    public var peers: [PeerStatus]
    /// State `dead`: why. Redacted.
    public var reason: String?
    /// The active check, when set; states `up` and `dead`.
    public var check: CheckStatus?

    public init(
        name: String, enabled: Bool, state: TunnelState, error: String? = nil, interface: String? = nil,
        addresses: [String] = [], routes: RouteMode = .config, routeCount: Int = 0,
        peers: [PeerStatus] = [], reason: String? = nil, check: CheckStatus? = nil
    ) {
        self.name = name
        self.enabled = enabled
        self.state = state
        self.error = error
        self.interface = interface
        self.addresses = addresses
        self.routes = routes
        self.routeCount = routeCount
        self.peers = peers
        self.reason = reason
        self.check = check
    }

    enum Keys: String, CodingKey {
        case name
        case enabled
        case state
        case error
        case interface
        case addresses
        case routes
        case routeCount = "route_count"
        case peers
        case reason
        case check
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        state = try c.decodeIfPresent(TunnelState.self, forKey: .state) ?? .off
        error = try c.decodeIfPresent(String.self, forKey: .error)
        interface = try c.decodeIfPresent(String.self, forKey: .interface)
        addresses = try c.decodeIfPresent([String].self, forKey: .addresses) ?? []
        routes = try c.decodeIfPresent(RouteMode.self, forKey: .routes) ?? .config
        routeCount = try c.decodeIfPresent(Int.self, forKey: .routeCount) ?? 0
        peers = try c.decodeIfPresent([PeerStatus].self, forKey: .peers) ?? []
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        check = try c.decodeIfPresent(CheckStatus.self, forKey: .check)
    }
}

/// One peer of a running tunnel.
public struct PeerStatus: Decodable, Equatable, Sendable {
    /// `Endpoint` as in the `.conf`. Redacted.
    public var endpoint: String?
    /// `addr:port` in use. Redacted.
    public var resolved: String?
    /// nil: never.
    public var lastHandshake: Date?
    public var rxBytes: Int
    public var txBytes: Int

    public init(
        endpoint: String? = nil, resolved: String? = nil, lastHandshake: Date? = nil,
        rxBytes: Int = 0, txBytes: Int = 0
    ) {
        self.endpoint = endpoint
        self.resolved = resolved
        self.lastHandshake = lastHandshake
        self.rxBytes = rxBytes
        self.txBytes = txBytes
    }

    enum Keys: String, CodingKey {
        case endpoint
        case resolved
        case lastHandshake = "last_handshake"
        case rxBytes = "rx_bytes"
        case txBytes = "tx_bytes"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        endpoint = try c.decodeIfPresent(String.self, forKey: .endpoint)
        resolved = try c.decodeIfPresent(String.self, forKey: .resolved)
        lastHandshake = try c.decodeIfPresent(String.self, forKey: .lastHandshake).map { try parseTime($0, c, .lastHandshake) }
        rxBytes = try c.decodeIfPresent(Int.self, forKey: .rxBytes) ?? 0
        txBytes = try c.decodeIfPresent(Int.self, forKey: .txBytes) ?? 0
    }
}

/// The active health check of a tunnel.
public struct CheckStatus: Decodable, Equatable, Sendable {
    /// Check address or URL. Redacted (nil).
    public var addr: String?
    /// nil: never.
    public var lastOK: Date?
    /// Round-trip time of the last successful check, ms.
    public var rttMs: Double?
    /// Consecutive failures.
    public var fails: Int

    public init(addr: String? = nil, lastOK: Date? = nil, rttMs: Double? = nil, fails: Int = 0) {
        self.addr = addr
        self.lastOK = lastOK
        self.rttMs = rttMs
        self.fails = fails
    }

    enum Keys: String, CodingKey {
        case addr
        case lastOK = "last_ok"
        case rttMs = "rtt_ms"
        case fails
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        addr = try c.decodeIfPresent(String.self, forKey: .addr)
        lastOK = try c.decodeIfPresent(String.self, forKey: .lastOK).map { try parseTime($0, c, .lastOK) }
        rttMs = try c.decodeIfPresent(Double.self, forKey: .rttMs)
        fails = try c.decodeIfPresent(Int.self, forKey: .fails) ?? 0
    }
}

/// One rule of `Status`; also used in `Explanation`.
public struct RuleStatus: Decodable, Equatable, Sendable {
    /// Index of the rule in the config, from 0.
    public var index: Int
    public var services: [String]
    /// Tunnels in priority order; empty: always direct.
    public var via: [String]
    public var fallback: Fallback
    /// The serving tunnel; nil when direct or in fallback.
    public var tunnel: String?
    public var inFallback: Bool
    /// `via` is not empty and the rule is not on `via[0]`.
    public var degraded: Bool
    /// Set only when `degraded`.
    public var reason: RuleReason?

    public init(
        index: Int, services: [String] = [], via: [String] = [], fallback: Fallback = .default,
        tunnel: String? = nil, inFallback: Bool = false, degraded: Bool = false, reason: RuleReason? = nil
    ) {
        self.index = index
        self.services = services
        self.via = via
        self.fallback = fallback
        self.tunnel = tunnel
        self.inFallback = inFallback
        self.degraded = degraded
        self.reason = reason
    }

    enum Keys: String, CodingKey {
        case index
        case services
        case via
        case fallback
        case tunnel
        case inFallback = "in_fallback"
        case degraded
        case reason
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        index = try c.decodeIfPresent(Int.self, forKey: .index) ?? 0
        services = try c.decodeIfPresent([String].self, forKey: .services) ?? []
        via = try c.decodeIfPresent([String].self, forKey: .via) ?? []
        fallback = try c.decodeIfPresent(Fallback.self, forKey: .fallback) ?? .default
        tunnel = try c.decodeIfPresent(String.self, forKey: .tunnel)
        inFallback = try c.decodeIfPresent(Bool.self, forKey: .inFallback) ?? false
        degraded = try c.decodeIfPresent(Bool.self, forKey: .degraded) ?? false
        reason = try c.decodeIfPresent(RuleReason.self, forKey: .reason)
    }
}

/// Result of `diag.explain`; `kind` decides which fields may be set.
public struct Explanation: Decodable, Equatable, Sendable {
    /// Normalized: lowercase, no trailing dot.
    public var query: String
    public var kind: ExplanationKind
    public var rule: RuleStatus?
    /// `domain`: best rule passed over because it is in fallback `default`.
    public var skipped: RuleStatus?
    /// `domain`: a tunnel name, `system` or `block`.
    public var upstream: String?
    public var zone: String?
    /// Redacted.
    public var servers: [String]
    public var dropAAAA: Bool
    /// Redacted.
    public var addrs: [String]
    /// `ip`: the longest-prefix route; nil: the system default applies.
    public var route: RouteInfo?

    public init(
        query: String, kind: ExplanationKind, rule: RuleStatus? = nil, skipped: RuleStatus? = nil,
        upstream: String? = nil, zone: String? = nil, servers: [String] = [], dropAAAA: Bool = false,
        addrs: [String] = [], route: RouteInfo? = nil
    ) {
        self.query = query
        self.kind = kind
        self.rule = rule
        self.skipped = skipped
        self.upstream = upstream
        self.zone = zone
        self.servers = servers
        self.dropAAAA = dropAAAA
        self.addrs = addrs
        self.route = route
    }

    enum Keys: String, CodingKey {
        case query
        case kind
        case rule
        case skipped
        case upstream
        case zone
        case servers
        case dropAAAA = "drop_aaaa"
        case addrs
        case route
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        query = try c.decodeIfPresent(String.self, forKey: .query) ?? ""
        kind = try c.decodeIfPresent(ExplanationKind.self, forKey: .kind) ?? .unknown("")
        rule = try c.decodeIfPresent(RuleStatus.self, forKey: .rule)
        skipped = try c.decodeIfPresent(RuleStatus.self, forKey: .skipped)
        upstream = try c.decodeIfPresent(String.self, forKey: .upstream)
        zone = try c.decodeIfPresent(String.self, forKey: .zone)
        servers = try c.decodeIfPresent([String].self, forKey: .servers) ?? []
        dropAAAA = try c.decodeIfPresent(Bool.self, forKey: .dropAAAA) ?? false
        addrs = try c.decodeIfPresent([String].self, forKey: .addrs) ?? []
        route = try c.decodeIfPresent(RouteInfo.self, forKey: .route)
    }
}

/// Result of `diag.routes`.
public struct Routes: Decodable, Equatable, Sendable {
    public var routes: [RouteInfo]
    /// Error of the last sync with the kernel; nil: none.
    public var syncError: String?

    public init(routes: [RouteInfo] = [], syncError: String? = nil) {
        self.routes = routes
        self.syncError = syncError
    }

    enum Keys: String, CodingKey {
        case routes
        case syncError = "sync_error"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        routes = try c.decodeIfPresent([RouteInfo].self, forKey: .routes) ?? []
        syncError = try c.decodeIfPresent(String.self, forKey: .syncError)
    }
}

/// One route of the table.
public struct RouteInfo: Decodable, Equatable, Sendable {
    /// CIDR.
    public var prefix: String
    public var target: RouteTarget
    public var tunnel: String?
    public var source: RouteSource
    /// Index of the rule in the config; -1: none.
    public var rule: Int
    /// `source: dynamic`: domain names. Redacted.
    public var names: [String]
    /// Why the route is not in the kernel; nil: it is.
    public var skipped: String?

    public init(
        prefix: String, target: RouteTarget, tunnel: String? = nil, source: RouteSource,
        rule: Int = -1, names: [String] = [], skipped: String? = nil
    ) {
        self.prefix = prefix
        self.target = target
        self.tunnel = tunnel
        self.source = source
        self.rule = rule
        self.names = names
        self.skipped = skipped
    }

    enum Keys: String, CodingKey {
        case prefix
        case target
        case tunnel
        case source
        case rule
        case names
        case skipped
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        prefix = try c.decodeIfPresent(String.self, forKey: .prefix) ?? ""
        target = try c.decodeIfPresent(RouteTarget.self, forKey: .target) ?? .unknown("")
        tunnel = try c.decodeIfPresent(String.self, forKey: .tunnel)
        source = try c.decodeIfPresent(RouteSource.self, forKey: .source) ?? .unknown("")
        rule = try c.decodeIfPresent(Int.self, forKey: .rule) ?? -1
        names = try c.decodeIfPresent([String].self, forKey: .names) ?? []
        skipped = try c.decodeIfPresent(String.self, forKey: .skipped)
    }
}

/// Result of `config.reload`.
public struct ApplyResult: Decodable, Equatable, Sendable {
    public var warnings: [String]
    /// Enabled tunnels that failed to start.
    public var tunnels: [TunnelError]

    public init(warnings: [String] = [], tunnels: [TunnelError] = []) {
        self.warnings = warnings
        self.tunnels = tunnels
    }

    enum Keys: String, CodingKey {
        case warnings
        case tunnels
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        warnings = try c.decodeIfPresent([String].self, forKey: .warnings) ?? []
        tunnels = try c.decodeIfPresent([TunnelError].self, forKey: .tunnels) ?? []
    }
}

/// A tunnel that failed to start (element of `ApplyResult.tunnels`).
public struct TunnelError: Decodable, Equatable, Sendable {
    public var name: String
    public var error: String

    public init(name: String, error: String) {
        self.name = name
        self.error = error
    }

    enum Keys: String, CodingKey {
        case name
        case error
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        error = try c.decodeIfPresent(String.self, forKey: .error) ?? ""
    }
}

/// Result of `tunnel.enable`.
public struct EnableResult: Decodable, Equatable, Sendable {
    /// The daemon is paused: the toggle is on, the tunnel comes up on resume.
    public var startsOnResume: Bool

    public init(startsOnResume: Bool = false) {
        self.startsOnResume = startsOnResume
    }

    enum Keys: String, CodingKey {
        case startsOnResume = "starts_on_resume"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        startsOnResume = try c.decodeIfPresent(Bool.self, forKey: .startsOnResume) ?? false
    }
}

/// Parses an RFC 3339 time, with or without fractional seconds. Independent
/// of the decoder's date strategy, so models decode with any `JSONDecoder`.
private func parseTime<K: CodingKey>(_ s: String, _ c: KeyedDecodingContainer<K>, _ key: K) throws -> Date {
    if let date = rfc3339Fractional.date(from: s) ?? rfc3339.date(from: s) {
        return date
    }
    throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "not an RFC 3339 time: \(s)")
}

// ISO8601DateFormatter is thread-safe (Foundation docs) but not Sendable.
nonisolated(unsafe) private let rfc3339Fractional: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

nonisolated(unsafe) private let rfc3339: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()
