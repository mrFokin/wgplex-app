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
        let status: Status
        switch state {
        case .notInstalled:
            return unavailable("wgplex не установлен")
        case .notRunning:
            return unavailable("Демон не запущен")
        case .outdated:
            return unavailable("Обновите wgplex")
        case .ready(let s):
            status = s
        }

        let tunnels = status.tunnels.map { t -> TunnelDetail in
            let first = t.peers.first
            let handshake: String?
            let traffic: String?
            if t.peers.isEmpty {
                handshake = nil
                traffic = nil
            } else {
                let last = t.peers.compactMap(\.lastHandshake).max()
                handshake = formatHandshake(secondsAgo: last.map { max(0, Int(now.timeIntervalSince($0))) })
                let rx = t.peers.reduce(0) { $0 + $1.rxBytes }
                let tx = t.peers.reduce(0) { $0 + $1.txBytes }
                traffic = "↓ \(formatBytes(rx)) ↑ \(formatBytes(tx))"
            }
            return TunnelDetail(
                row: MenuModel.row(of: t, status: status, startsOnResume: startsOnResume),
                endpoint: first?.endpoint, interface: t.interface, addresses: t.addresses,
                handshakeText: handshake, trafficText: traffic, routeCount: t.routeCount,
                checkText: t.check.map(checkText), error: t.error, reason: t.reason)
        }

        let rules = status.rules.map { r -> RuleRow in
            let state: String
            if r.inFallback {
                state = "без туннеля"
            } else if r.degraded {
                state = "на резерве"
            } else if r.via.isEmpty {
                state = "напрямую"
            } else {
                state = "ok"
            }
            return RuleRow(
                index: r.index, services: r.services, via: r.via, tunnel: r.tunnel, stateText: state,
                isProblem: MenuModel.isProblem(r), reasonText: reasonText(r.reason))
        }

        var banner: Banner?
        if status.configErrorCount > 0 {
            banner = Banner(kind: .configError, text: "ошибка конфига", target: .config)
        } else if status.paused {
            banner = Banner(kind: .paused, text: "Приостановлено", target: .config)
        } else if let p = MenuModel.problem(of: status), case .rule = p.target {
            banner = Banner(kind: .ruleFallback, text: p.text, target: p.target)
        }

        return WindowModel(
            banner: banner,
            actions: ActionBar(
                pauseTitle: status.paused ? "Возобновить" : "Приостановить",
                pauseEnabled: status.canControl, disableAllEnabled: status.canControl,
                reloadEnabled: status.canControl),
            tunnels: tunnels, rules: rules)
    }

    private static func unavailable(_ text: String) -> WindowModel {
        WindowModel(
            banner: Banner(kind: .daemonUnavailable, text: text, target: .daemon),
            actions: ActionBar(
                pauseTitle: "Приостановить", pauseEnabled: false, disableAllEnabled: false,
                reloadEnabled: false),
            tunnels: [], rules: [])
    }

    private static func checkText(_ c: CheckStatus) -> String {
        if c.fails > 0 { return "сбоев: \(c.fails)" }
        if let rtt = c.rttMs { return "ok, \(Int(rtt.rounded())) мс" }
        return "ok"
    }

    private static func reasonText(_ r: RuleReason?) -> String? {
        switch r {
        case .dead: return "туннель недоступен"
        case .disabled: return "туннель выключен"
        case .paused: return "пауза"
        case nil, .unknown: return nil
        }
    }

    /// Human-readable size: "0 Б", "512 Б", "1,5 КБ", "12 МБ", "3,2 ГБ" (base 1024,
    /// one decimal below 10 units, decimal comma).
    public static func formatBytes(_ bytes: Int) -> String {
        let units = ["Б", "КБ", "МБ", "ГБ", "ТБ"]
        var value = Double(max(0, bytes))
        var unit = 0
        while value >= 1024 && unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        if unit == 0 { return "\(Int(value)) \(units[0])" }
        // Rounding may carry into the next unit ("1024 КБ" -> "1,0 МБ").
        if value.rounded() >= 1024 && unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        if value < 9.95 {
            let tenths = Int((value * 10).rounded())
            return "\(tenths / 10),\(tenths % 10) \(units[unit])"
        }
        return "\(Int(value.rounded())) \(units[unit])"
    }

    /// "N с назад" (N seconds, minutes and hours may be folded into larger units),
    /// "нет" when nil (never).
    public static func formatHandshake(secondsAgo: Int?) -> String {
        guard let s = secondsAgo else { return "нет" }
        let n = max(0, s)
        if n < 60 { return "\(n) с назад" }
        if n < 3600 { return "\(n / 60) мин назад" }
        return "\(n / 3600) ч назад"
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
        canRead ? .open(path) : .adminOnly(path)
    }

    /// "Конфиг правит администратор" for `adminOnly`; nil for `open`.
    public var note: String? {
        switch self {
        case .open: return nil
        case .adminOnly: return "Конфиг правит администратор"
        }
    }
}
