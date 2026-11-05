import Foundation

/// Kind of the window banner (design 5). Priority, highest first:
/// `configError`, `daemonUnavailable`, `paused`, `ruleFallback`.
public enum BannerKind: Equatable, Sendable {
    case configError
    case daemonUnavailable
    case paused
    case ruleFallback
}

/// The banner on top of the window.
public struct Banner: Equatable, Sendable {
    public var kind: BannerKind
    /// Display text in Russian.
    public var text: String
    /// Section the banner leads to.
    public var target: ProblemTarget

    public init(kind: BannerKind, text: String, target: ProblemTarget) {
        self.kind = kind
        self.text = text
        self.target = target
    }
}

/// State of the action bar buttons.
public struct ActionBar: Equatable, Sendable {
    /// "Приостановить" or "Возобновить".
    public var pauseTitle: String
    /// Ready and `can_control`.
    public var pauseEnabled: Bool
    /// "Выключить все": ready and `can_control`.
    public var disableAllEnabled: Bool
    /// "Перечитать конфиг": ready and `can_control`.
    public var reloadEnabled: Bool

    public init(pauseTitle: String, pauseEnabled: Bool, disableAllEnabled: Bool, reloadEnabled: Bool) {
        self.pauseTitle = pauseTitle
        self.pauseEnabled = pauseEnabled
        self.disableAllEnabled = disableAllEnabled
        self.reloadEnabled = reloadEnabled
    }
}

/// A tunnel in the window: the list row plus the details.
public struct TunnelDetail: Equatable, Sendable {
    /// Flags as in the menu (`checked`, `warn`, `dimmed`, `enabled`, `startsOnResume`).
    public var row: TunnelRow
    /// Endpoint of the first peer; nil when unknown or redacted.
    public var endpoint: String?
    /// `utunN`; nil when the tunnel is not up.
    public var interface: String?
    public var addresses: [String]
    /// "N с назад" or "нет" (see `WindowModel.formatHandshake`); nil without peers.
    public var handshakeText: String?
    /// "↓ 1,2 МБ ↑ 340 КБ", summed over peers; nil without peers.
    public var trafficText: String?
    public var routeCount: Int
    /// Check summary in Russian ("ok, 12 мс", "сбоев: 3"); nil without a check.
    public var checkText: String?
    /// State `error`: why the tunnel failed to start.
    public var error: String?
    /// State `dead`: why.
    public var reason: String?

    public init(
        row: TunnelRow, endpoint: String?, interface: String?, addresses: [String],
        handshakeText: String?, trafficText: String?, routeCount: Int, checkText: String?,
        error: String?, reason: String?
    ) {
        self.row = row
        self.endpoint = endpoint
        self.interface = interface
        self.addresses = addresses
        self.handshakeText = handshakeText
        self.trafficText = trafficText
        self.routeCount = routeCount
        self.checkText = checkText
        self.error = error
        self.reason = reason
    }
}

/// One row of the rules list.
public struct RuleRow: Equatable, Sendable {
    public var index: Int
    /// Services of the rule, in config order.
    public var services: [String]
    public var via: [String]
    /// The serving tunnel; nil when direct or in fallback.
    public var tunnel: String?
    /// State text in Russian ("на резерве", "без туннеля", "напрямую", "ok").
    public var stateText: String
    /// The state is a problem (same criterion as the menu problem row).
    public var isProblem: Bool
    /// Reason text for a degraded rule; nil otherwise.
    public var reasonText: String?

    public init(
        index: Int, services: [String], via: [String], tunnel: String?, stateText: String,
        isProblem: Bool, reasonText: String?
    ) {
        self.index = index
        self.services = services
        self.via = via
        self.tunnel = tunnel
        self.stateText = stateText
        self.isProblem = isProblem
        self.reasonText = reasonText
    }
}

/// Everything the window shows, computed from `EngineState` (design 5). Pure
/// data, no AppKit.
public struct WindowModel: Equatable, Sendable {
    /// Nil when there is nothing to report.
    public var banner: Banner?
    public var actions: ActionBar
    /// In the order of `status.tunnels`; empty when unavailable.
    public var tunnels: [TunnelDetail]
    /// In the order of `status.rules`; empty when unavailable.
    public var rules: [RuleRow]

    public init(banner: Banner?, actions: ActionBar, tunnels: [TunnelDetail], rules: [RuleRow]) {
        self.banner = banner
        self.actions = actions
        self.tunnels = tunnels
        self.rules = rules
    }

    /// Builds the window model.
    ///
    /// - Parameters:
    ///   - state: engine state from `Engine.locate`.
    ///   - startsOnResume: tunnels for which `tunnel.enable` returned `starts_on_resume`.
    ///   - now: reference time for the handshake age.
    public static func make(
        from state: EngineState, startsOnResume: Set<String> = [], now: Date = Date()
    ) -> WindowModel {
        fatalError("not implemented")
    }

    /// Human-readable size: "0 Б", "512 Б", "1,5 КБ", "12 МБ", "3,2 ГБ" (base 1024,
    /// one decimal below 10 units, decimal comma).
    public static func formatBytes(_ bytes: Int) -> String {
        fatalError("not implemented")
    }

    /// "N с назад" (N seconds, minutes and hours may be folded into larger units),
    /// "нет" when nil (never).
    public static func formatHandshake(secondsAgo: Int?) -> String {
        fatalError("not implemented")
    }
}

/// Whether the current user can open `config_dir` (design 5).
public enum ConfigDirAccess: Equatable, Sendable {
    /// Readable: offer "Открыть папку конфига".
    case open(String)
    /// Not readable: show the path and the note "Конфиг правит администратор".
    case adminOnly(String)

    /// - Parameters:
    ///   - path: `config_dir` from the status.
    ///   - canRead: result of the readability check done by the caller.
    public static func describe(path: String, canRead: Bool) -> ConfigDirAccess {
        fatalError("not implemented")
    }

    /// "Конфиг правит администратор" for `adminOnly`; nil for `open`.
    public var note: String? {
        fatalError("not implemented")
    }
}
