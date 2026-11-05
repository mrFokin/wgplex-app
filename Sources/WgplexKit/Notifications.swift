import Foundation

/// A notification to show (design 7). Texts are in Russian.
public struct AppNotification: Equatable, Sendable {
    /// Bold first line.
    public var title: String
    /// Detail line, e.g. "youtube, ai → de".
    public var body: String
    /// Window section a click opens.
    public var target: ProblemTarget

    public init(title: String, body: String, target: ProblemTarget) {
        self.title = title
        self.body = body
        self.target = target
    }
}

/// Compares neighbouring polls and decides what to notify about (design 7).
/// State is a value; the caller keeps it between polls.
public struct NotificationPlanner: Equatable, Sendable {
    /// Anti-flap window per tunnel: 5 minutes.
    public static let flapInterval: TimeInterval = 5 * 60

    /// Last notification time per tunnel name (anti-flap).
    public var lastNotified: [String: Date]

    /// Set by `noteOwnReload()`; consumed by the next `plan` call.
    public private(set) var ownReloadPending = false

    public init(lastNotified: [String: Date] = [:]) {
        self.lastNotified = lastNotified
    }

    /// The user's own "Перечитать конфиг" has finished (call after the RPC completes). The next
    /// `plan` drops the config-error event and the tunnel `dead`/`error` events it caused (the
    /// window already shows the result), before events are merged.
    public mutating func noteOwnReload() {
        ownReloadPending = true
    }

    /// Plans notifications for one poll.
    ///
    /// - Parameters:
    ///   - prev: state of the previous poll; nil for the first poll after the app starts
    ///     (only remembered, returns `[]`: an old problem is not announced).
    ///   - next: state of this poll.
    ///   - now: current time.
    /// - Returns: at most one merged notification per poll (events of one poll are combined;
    ///   several → one with a combined body, target of the first). Events:
    ///   - a tunnel went `dead`/`error` while enabled and rules moved to a fallback or reserve
    ///     with `reason: dead` -> "nl не отвечает", body "youtube, ai → de" (`.tunnel`);
    ///   - recovery of such a tunnel -> "nl снова работает" (`.tunnel`);
    ///   - config errors (`config_error_count` > 0) and the count grew or `config_errors` changed
    ///     (so a repeated failed reload with another text counts too): "wgplex запущен без туннелей:
    ///     конфиг с ошибками" when `next.configured == false`, otherwise "Изменения конфига не
    ///     применены: N ошибок…" (`.config`);
    ///   - `ready` -> `notRunning` "wgplex не работает"; back to `ready` -> "wgplex снова работает" (`.daemon`).
    ///   Silent: pause, enable/disable, rules with `reason: disabled|paused`, `notInstalled`/`outdated`,
    ///   and the same tunnel again within `flapInterval` of its last notification (updates `lastNotified`
    ///   only when a notification is produced), and the config/`dead` events caused by the user's own
    ///   reload (`noteOwnReload()`), dropped before merging.
    public mutating func plan(prev: EngineState?, next: EngineState, now: Date) -> [AppNotification] {
        guard let prev else { return [] }
        var events: [AppNotification] = []

        let ownReload = ownReloadPending
        ownReloadPending = false
        let prevStatus = Self.status(of: prev)
        let nextStatus = Self.status(of: next)

        // Tunnel events, in the order of the next status (then tunnels that vanished).
        if let nextStatus {
            for t in nextStatus.tunnels {
                let wasDown = prevStatus.flatMap { Self.affectedRules(of: t.name, in: $0) }
                let nowDown = Self.affectedRules(of: t.name, in: nextStatus)
                var event: AppNotification?
                if let nowDown, wasDown == nil {
                    if ownReload { continue }
                    let targets = Self.unique(nowDown.map { $0.tunnel ?? Self.fallbackText($0) })
                    event = AppNotification(
                        title: "\(t.name) не отвечает",
                        body: Self.services(nowDown) + " → " + targets.joined(separator: ", "),
                        target: .tunnel(t.name))
                } else if let wasDown, nowDown == nil, t.enabled, t.state == .up {
                    let indexes = Set(wasDown.map(\.index))
                    let served = nextStatus.rules.filter { indexes.contains($0.index) && $0.tunnel == t.name }
                    event = AppNotification(
                        title: "\(t.name) снова работает",
                        body: served.isEmpty ? "" : Self.services(served) + " через " + t.name,
                        target: .tunnel(t.name))
                }
                if let event {
                    if let last = lastNotified[t.name], now.timeIntervalSince(last) < Self.flapInterval {
                        continue
                    }
                    lastNotified[t.name] = now
                    events.append(event)
                }
            }
        }

        // Config errors.
        if let ns = nextStatus, ns.configErrorCount > 0, !ownReload {
            let n = ns.configErrorCount
            let changed = prevStatus.map {
                n > $0.configErrorCount || ns.configErrors != $0.configErrors
            } ?? true
            if changed {
                if ns.configured {
                    events.append(AppNotification(
                        title: "Изменения конфига не применены: \(Self.errors(n))",
                        body: "Работает прежний конфиг", target: .config))
                } else {
                    events.append(AppNotification(
                        title: "wgplex запущен без туннелей: конфиг с ошибками", body: "", target: .config))
                }
            }
        }

        // Daemon.
        if prevStatus != nil, case .notRunning = next {
            events.append(AppNotification(title: "wgplex не работает", body: "", target: .daemon))
        } else if case .notRunning = prev, nextStatus != nil {
            events.append(AppNotification(title: "wgplex снова работает", body: "", target: .daemon))
        }

        guard var merged = events.first else { return [] }
        if events.count > 1 {
            merged.body = events.enumerated().map { i, e in
                if i == 0 { return e.body }
                return e.body.isEmpty ? e.title : e.title + ": " + e.body
            }.filter { !$0.isEmpty }.joined(separator: "\n")
        }
        return [merged]
    }

    private static func status(of state: EngineState) -> Status? {
        if case .ready(let s) = state { return s }
        return nil
    }

    /// Rules pushed off tunnel `name` because it is dead; nil when the tunnel is fine or no
    /// rule moved because of it.
    private static func affectedRules(of name: String, in status: Status) -> [RuleStatus]? {
        guard let t = status.tunnels.first(where: { $0.name == name }),
            t.enabled, t.state == .dead || t.state == .error
        else { return nil }
        let rules = status.rules.filter {
            $0.via.contains(name) && ($0.degraded || $0.inFallback) && $0.reason == .dead
                && $0.tunnel != name
        }
        return rules.isEmpty ? nil : rules
    }

    private static func services(_ rules: [RuleStatus]) -> String {
        unique(rules.flatMap(\.services)).joined(separator: ", ")
    }

    private static func fallbackText(_ r: RuleStatus) -> String {
        if case .block = r.fallback { return "блокировка" }
        return "напрямую"
    }

    private static func unique(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }

    /// "1 ошибка", "2 ошибки", "5 ошибок".
    private static func errors(_ n: Int) -> String {
        let m100 = n % 100, m10 = n % 10
        if m100 >= 11 && m100 <= 14 || m10 == 0 || m10 >= 5 { return "\(n) ошибок" }
        return m10 == 1 ? "\(n) ошибка" : "\(n) ошибки"
    }

    /// "Доступна Wgplex 1.3" (title), body with the upgrade command. `ProblemTarget` has no
    /// update case, so the target is `.daemon`; the app opens the window at the top, where
    /// the update banner is. Callers gate it with `UpdateCheck.shouldNotify`.
    public static func notification(for update: UpdateInfo) -> AppNotification {
        AppNotification(
            title: "Доступна Wgplex \(update.version)", body: update.command, target: .daemon)
    }
}
