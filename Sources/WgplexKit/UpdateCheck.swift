import Foundation

/// A newer app release (design 2): shown as the window banner and as a notification.
public struct UpdateInfo: Equatable, Sendable {
    /// Version without a leading "v" ("1.3.0").
    public var version: String
    /// Release page (`html_url`).
    public var url: String
    /// Always `brew upgrade --cask wgplex-app`.
    public var command: String

    public init(version: String, url: String, command: String = "brew upgrade --cask wgplex-app") {
        self.version = version
        self.url = url
        self.command = command
    }
}

/// Update check against `GET https://api.github.com/repos/mrFokin/wgplex-app/releases/latest`.
/// Pure logic: the network is a closure, the clock is a parameter.
public struct UpdateCheck: Equatable, Sendable {
    /// Minimum interval between checks: 24 hours.
    public static let interval: TimeInterval = 24 * 3600

    /// When the last check was started; nil if never.
    public var lastCheck: Date?
    /// Version we have already notified about; nil if none.
    public var notifiedVersion: String?

    public init(lastCheck: Date? = nil, notifiedVersion: String? = nil) {
        self.lastCheck = lastCheck
        self.notifiedVersion = notifiedVersion
    }

    /// Parses the `releases/latest` body. Reads `tag_name` (leading "v" stripped) and `html_url`.
    /// - Returns: nil for invalid JSON, a missing/empty field, or a non-numeric version.
    public static func parse(_ data: Data) -> UpdateInfo? {
        fatalError("not implemented")
    }

    /// Whether `candidate` is newer than `current` (`appVersion` by default).
    /// Compares dot-separated numeric components, missing ones count as 0 ("1.3" == "1.3.0");
    /// a pre-release suffix after "-" ("0.1.0-dev") sorts below the same release version.
    /// An unparsable version is never newer.
    public static func isNewer(_ candidate: String, than current: String = appVersion) -> Bool {
        fatalError("not implemented")
    }

    /// True when `lastCheck` is nil or at least `interval` seconds before `now`.
    /// A `lastCheck` in the future (clock moved back) counts as due.
    public func isDue(now: Date) -> Bool {
        fatalError("not implemented")
    }

    /// Runs one check if due: records `lastCheck = now` (also on failure, so a broken
    /// network is retried only after the interval), loads and parses via `fetch`.
    /// - Returns: the update when it is newer than `current`; nil when not due, up to date,
    ///   or on any failure (network error, 404 because the repository has no releases yet,
    ///   bad JSON) — failures are silent.
    public mutating func check(
        now: Date, current: String = appVersion, fetch: () async throws -> Data
    ) async -> UpdateInfo? {
        fatalError("not implemented")
    }

    /// For the notification: returns true once per version and remembers it in
    /// `notifiedVersion`; false for the same version again. A newer version notifies again.
    public mutating func shouldNotify(_ update: UpdateInfo) -> Bool {
        fatalError("not implemented")
    }
}
