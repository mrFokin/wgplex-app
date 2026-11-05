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

    public init(lastNotified: [String: Date] = [:]) {
        self.lastNotified = lastNotified
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
    ///   - `config_error_count` grew: "Изменения конфига не применены: N ошибок…" when `prev`
    ///     was `ready`; "wgplex запущен без туннелей: конфиг с ошибками" when the daemon has
    ///     just started (`prev` not `ready`) (`.config`);
    ///   - `ready` -> `notRunning` "wgplex не работает"; back to `ready` -> "wgplex снова работает" (`.daemon`).
    ///   Silent: pause, enable/disable, rules with `reason: disabled|paused`, `notInstalled`/`outdated`,
    ///   and the same tunnel again within `flapInterval` of its last notification (updates `lastNotified`
    ///   only when a notification is produced).
    public mutating func plan(prev: EngineState?, next: EngineState, now: Date) -> [AppNotification] {
        fatalError("not implemented")
    }

    /// "Доступна Wgplex 1.3" (title), body with the upgrade command. `ProblemTarget` has no
    /// update case, so the target is `.daemon`; the app opens the window at the top, where
    /// the update banner is. Callers gate it with `UpdateCheck.shouldNotify`.
    public static func notification(for update: UpdateInfo) -> AppNotification {
        fatalError("not implemented")
    }
}
