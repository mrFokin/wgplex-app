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
        NSApp.setActivationPolicy(.accessory)
    }
}
