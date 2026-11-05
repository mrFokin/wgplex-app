import AppKit
import SwiftUI
import WgplexKit

/// The single Wgplex window. The Dock icon exists only while it is open (design 5).
@MainActor
final class WindowController: NSObject, NSWindowDelegate {
    let state: WindowState
    private var window: NSWindow?

    init(poller: StatusPoller) {
        state = WindowState(poller: poller)
    }

    /// Opens the window (or brings it forward), optionally on a section.
    func show(section: WindowSection? = nil) {
        if let section { state.section = section }
        let window = self.window ?? makeWindow()
        self.window = window
        if window.contentView == nil { window.contentView = hostingView() }
        state.poller.setWindowOpen(true)
        state.poller.poll()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        w.title = "Wgplex"
        w.isReleasedWhenClosed = false
        w.contentMinSize = NSSize(width: 700, height: 440)
        w.contentView = hostingView()
        w.center()
        w.delegate = self
        return w
    }

    private func hostingView() -> NSView {
        NSHostingView(rootView: WindowRootView(state: state))
    }

    func windowWillClose(_ notification: Notification) {
        state.poller.setWindowOpen(false)
        // Drop the views so section tasks (log reading) stop while the window is closed.
        window?.contentView = nil
        dropDockIcon(closing: window)
    }
}

/// Settings window; like the main one it has a Dock icon while open.
@MainActor
final class SettingsController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let settings: Settings
    private let loginItem: LoginItem
    private let onNotificationsOn: () -> Void
    private let onUpdatesChanged: () -> Void

    init(
        settings: Settings, loginItem: LoginItem, onNotificationsOn: @escaping () -> Void,
        onUpdatesChanged: @escaping () -> Void
    ) {
        self.settings = settings
        self.loginItem = loginItem
        self.onNotificationsOn = onNotificationsOn
        self.onUpdatesChanged = onUpdatesChanged
    }

    func show() {
        let w = window ?? makeWindow()
        window = w
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 180),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Настройки Wgplex"
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: SettingsView(
            settings: settings, loginItem: loginItem, onNotificationsOn: onNotificationsOn,
            onUpdatesChanged: onUpdatesChanged))
        w.center()
        w.delegate = self
        return w
    }

    func windowWillClose(_ notification: Notification) {
        dropDockIcon(closing: window)
    }
}

/// Back to a menu-bar-only app when no titled window of ours stays open.
@MainActor
private func dropDockIcon(closing: NSWindow?) {
    let open = NSApp.windows.contains {
        $0 !== closing && $0.isVisible && $0.styleMask.contains(.titled)
    }
    if !open { NSApp.setActivationPolicy(.accessory) }
}
