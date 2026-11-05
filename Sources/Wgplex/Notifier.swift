import Foundation
import UserNotifications
import WgplexKit

/// Shows `AppNotification`s through `UNUserNotificationCenter`; a click opens the window
/// on the notification's section. Does nothing without an app bundle.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// Called on a click with the section to open.
    var onOpen: ((ProblemTarget) -> Void)?

    override init() {
        super.init()
        if Settings.hasBundle { UNUserNotificationCenter.current().delegate = self }
    }

    /// Asks for permission (the system shows its prompt once).
    func requestAuthorization() {
        guard Settings.hasBundle else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(_ n: AppNotification) {
        guard Settings.hasBundle else { return }
        let content = UNMutableNotificationContent()
        content.title = n.title
        content.body = n.body
        content.userInfo = ["target": Self.encode(n.target)]
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    private static func encode(_ t: ProblemTarget) -> String {
        switch t {
        case .rule(let i): return "rule:\(i)"
        case .tunnel(let name): return "tunnel:\(name)"
        case .config: return "config"
        case .daemon: return "daemon"
        }
    }

    private static func decode(_ s: String) -> ProblemTarget {
        if s.hasPrefix("rule:"), let i = Int(s.dropFirst(5)) { return .rule(i) }
        if s.hasPrefix("tunnel:") { return .tunnel(String(s.dropFirst(7))) }
        return s == "config" ? .config : .daemon
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Show banners even while the app is "active" (e.g. its window is open).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let raw = response.notification.request.content.userInfo["target"] as? String ?? "daemon"
        await MainActor.run { onOpen?(Self.decode(raw)) }
    }
}
