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

/// Outcome of `UpdateCheck.check`.
public enum UpdateCheckResult: Equatable, Sendable {
    /// Less than `interval` since the last check: nothing was fetched.
    case notDue
    /// Network error, bad status or unparsable body: keep what was stored.
    case failed
    /// The answer is valid and there is no newer release.
    case upToDate
    /// A newer release.
    case available(UpdateInfo)
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
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            var tag = obj["tag_name"] as? String, let url = obj["html_url"] as? String,
            !url.isEmpty
        else { return nil }
        if tag.hasPrefix("v") { tag.removeFirst() }
        guard parseVersion(tag) != nil else { return nil }
        return UpdateInfo(version: tag, url: url)
    }

    /// Whether `candidate` is newer than `current` (`appVersion` by default).
    /// Compares dot-separated numeric components, missing ones count as 0 ("1.3" == "1.3.0");
    /// a pre-release suffix after "-" ("0.1.0-dev") sorts below the same release version.
    /// An unparsable version is never newer.
    public static func isNewer(_ candidate: String, than current: String = appVersion) -> Bool {
        guard let c = parseVersion(candidate), let cur = parseVersion(current) else { return false }
        let n = max(c.parts.count, cur.parts.count)
        for i in 0..<n {
            let a = i < c.parts.count ? c.parts[i] : 0
            let b = i < cur.parts.count ? cur.parts[i] : 0
            if a != b { return a > b }
        }
        // Equal numbers: a pre-release sorts below the release.
        return !c.pre && cur.pre
    }

    /// True when `lastCheck` is nil or at least `interval` seconds before `now`.
    /// A `lastCheck` in the future (clock moved back) counts as due.
    public func isDue(now: Date) -> Bool {
        guard let last = lastCheck else { return true }
        let elapsed = now.timeIntervalSince(last)
        return elapsed >= Self.interval || elapsed < 0
    }

    /// Runs one check if due: records `lastCheck = now` (also on failure, so a broken
    /// network is retried only after the interval), loads and parses via `fetch`.
    /// - Returns: `.available` when newer than `current`; `.upToDate` for a valid answer without
    ///   a newer release; `.failed` on any failure (network error, 404 because the repository
    ///   has no releases yet, bad JSON) — silent, stored data stays; `.notDue` when not due.
    public mutating func check(
        now: Date, current: String = appVersion, fetch: () async throws -> Data
    ) async -> UpdateCheckResult {
        guard isDue(now: now) else { return .notDue }
        lastCheck = now
        guard let data = try? await fetch(), let info = Self.parse(data) else { return .failed }
        return Self.isNewer(info.version, than: current) ? .available(info) : .upToDate
    }

    /// For the notification: returns true once per version and remembers it in
    /// `notifiedVersion`; false for the same version again. A newer version notifies again.
    public mutating func shouldNotify(_ update: UpdateInfo) -> Bool {
        guard notifiedVersion != update.version else { return false }
        notifiedVersion = update.version
        return true
    }

    /// Numeric components and whether a "-suffix" is present; nil when unparsable.
    private static func parseVersion(_ v: String) -> (parts: [Int], pre: Bool)? {
        let pieces = v.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard let core = pieces.first, !core.isEmpty else { return nil }
        var parts: [Int] = []
        for p in core.split(separator: ".", omittingEmptySubsequences: false) {
            guard !p.isEmpty, p.allSatisfy({ $0.isASCII && $0.isNumber }), let n = Int(p) else { return nil }
            parts.append(n)
        }
        return (parts, pieces.count > 1)
    }
}
