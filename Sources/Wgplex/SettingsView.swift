import AppKit
import SwiftUI

/// Settings window content (design 5): launch at login, notifications, update check.
struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var loginItem: LoginItem
    /// Asks the system for notification permission when the user turns them on.
    var onNotificationsOn: () -> Void
    var onUpdatesChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Запускать при входе", isOn: Binding(
                get: { loginItem.isOn }, set: { loginItem.set($0) }))
                .disabled(!Settings.hasBundle)
            if loginItem.needsApproval {
                note("Разрешите Wgplex в Системные настройки → Основные → Объекты входа.")
            }
            if let error = loginItem.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            Toggle("Уведомления", isOn: Binding(
                get: { settings.notifications },
                set: {
                    settings.notifications = $0
                    if $0 { onNotificationsOn() }
                }))
                .disabled(!Settings.hasBundle)

            Toggle("Проверять обновления", isOn: Binding(
                get: { settings.checkUpdates },
                set: {
                    settings.checkUpdates = $0
                    onUpdatesChanged()
                }))

            if !Settings.hasBundle {
                note("Автозапуск и уведомления: нужна сборка .app.")
            }
        }
        .padding(20)
        .frame(width: 380, alignment: .leading)
        .onAppear { loginItem.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem.refresh()
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }
}
