import Foundation
import WgplexKit

/// Daily update check against the GitHub releases API (design 2). The state
/// (`lastCheck`, notified version, last found release) lives in `UserDefaults`.
@MainActor
final class Updater {
    nonisolated static let releasesURL = URL(string: "https://api.github.com/repos/mrFokin/wgplex-app/releases/latest")!

    /// Called with the newer release, or nil when there is none (or checks are off).
    var onUpdate: ((UpdateInfo?) -> Void)?
    /// Called once per version when a notification should be shown.
    var onNotify: ((UpdateInfo) -> Void)?

    private let settings: Settings
    private let defaults: UserDefaults
    private var check: UpdateCheck
    private var found: UpdateInfo?
    private var running = false
    private var timer: Timer?

    init(settings: Settings, defaults: UserDefaults = .standard) {
        self.settings = settings
        self.defaults = defaults
        check = UpdateCheck(
            lastCheck: defaults.object(forKey: "update.lastCheck") as? Date,
            notifiedVersion: defaults.string(forKey: "update.notifiedVersion"))
        if let v = defaults.string(forKey: "update.version"), let u = defaults.string(forKey: "update.url") {
            found = UpdateInfo(version: v, url: u)
        }
    }

    /// Runs a check now (it only goes to the network when a day has passed) and then hourly.
    func start() {
        publish()
        run()
        let t = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.run() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Re-applies the setting: hides the banner when off, checks when switched on.
    func settingsChanged() {
        publish()
        run()
    }

    /// The remembered release if it is still newer than this app.
    private func publish() {
        if settings.checkUpdates, let found, UpdateCheck.isNewer(found.version) {
            onUpdate?(found)
        } else {
            onUpdate?(nil)
        }
    }

    private func run() {
        guard settings.checkUpdates, !running else { return }
        running = true
        var local = check
        Task {
            let result = await local.check(now: Date(), fetch: Self.fetch)
            running = false
            guard settings.checkUpdates else { return }
            check = local
            defaults.set(check.lastCheck, forKey: "update.lastCheck")
            switch result {
            case .available(let info):
                found = info
                defaults.set(info.version, forKey: "update.version")
                defaults.set(info.url, forKey: "update.url")
                if settings.notifications, check.shouldNotify(info) {
                    defaults.set(check.notifiedVersion, forKey: "update.notifiedVersion")
                    onNotify?(info)
                }
            case .upToDate:
                // A valid answer without a newer release (e.g. a withdrawn one): forget the old find.
                found = nil
                defaults.removeObject(forKey: "update.version")
                defaults.removeObject(forKey: "update.url")
            case .failed, .notDue:
                break
            }
            publish()
        }
    }

    /// Body of the `releases/latest` response; non-2xx (e.g. 404) throws.
    private nonisolated static func fetch() async throws -> Data {
        var request = URLRequest(url: releasesURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Wgplex/\(appVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
