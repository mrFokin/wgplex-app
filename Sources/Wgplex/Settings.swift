import Foundation

/// App preferences in `UserDefaults`. "Launch at login" is not here: it is the state
/// of `SMAppService.mainApp` (see `LoginItem`).
@MainActor
final class Settings: ObservableObject {
    /// True when running from a `.app` bundle. `UNUserNotificationCenter` and `SMAppService`
    /// crash without one (`swift run`), so the app disables them then.
    static let hasBundle = Bundle.main.bundleIdentifier != nil

    private let defaults: UserDefaults

    @Published var checkUpdates: Bool {
        didSet { defaults.set(checkUpdates, forKey: "checkUpdates") }
    }
    @Published var notifications: Bool {
        didSet { defaults.set(notifications, forKey: "notifications") }
    }

    /// The first-run question has been shown.
    var firstRunDone: Bool {
        get { defaults.bool(forKey: "firstRunDone") }
        set { defaults.set(newValue, forKey: "firstRunDone") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        checkUpdates = defaults.object(forKey: "checkUpdates") as? Bool ?? true
        notifications = defaults.object(forKey: "notifications") as? Bool ?? true
    }
}
