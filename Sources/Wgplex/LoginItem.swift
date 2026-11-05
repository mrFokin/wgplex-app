import Foundation
import ServiceManagement

/// Launch at login via `SMAppService.mainApp` (design 6). Registers or unregisters
/// only on a user action; nothing here runs on its own.
@MainActor
final class LoginItem: ObservableObject {
    @Published private(set) var status: SMAppService.Status = .notRegistered
    /// Text of the last register/unregister failure, shown in the settings window.
    @Published var error: String?

    init() { refresh() }

    /// On in the toggle: registered, possibly waiting for approval.
    var isOn: Bool { status == .enabled || status == .requiresApproval }

    var needsApproval: Bool { status == .requiresApproval }

    /// Re-reads the system state (the user may change it in System Settings).
    func refresh() {
        guard Settings.hasBundle else { return }
        status = SMAppService.mainApp.status
    }

    /// User action: register or unregister the app as a login item.
    func set(_ on: Bool) {
        guard Settings.hasBundle else { return }
        error = nil
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            self.error = "Не удалось \(on ? "включить" : "выключить") автозапуск: \(error.localizedDescription)"
        }
        refresh()
    }
}
