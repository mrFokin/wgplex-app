import AppKit
import WgplexKit

/// The menu-bar item and its menu (design 4).
@MainActor
final class StatusController: NSObject, NSMenuDelegate {
    /// Page opened by "Как установить…".
    static let installURL = URL(string: "https://github.com/mrFokin/wgplex-app")!

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let poller = StatusPoller()
    private var state: EngineState = .notRunning
    private var model = MenuModel.make(from: .notRunning)
    /// Tunnels enabled while paused; kept until resume or a status without pause.
    private var startsOnResume: Set<String> = []
    /// Action error shown in the menu until the next poll.
    private var errorText: String?

    override init() {
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        item.button?.image = Icons.image(for: model.icon)
        poller.onState = { [weak self] in self?.apply($0) }
        poller.start()
    }

    private func apply(_ new: EngineState) {
        state = new
        if case .ready(let s) = new, !s.paused { startsOnResume = [] }
        errorText = nil
        rebuild()
    }

    /// Rebuilds the items in place; works while the menu is open.
    private func rebuild() {
        model = MenuModel.make(from: state, startsOnResume: startsOnResume)
        item.button?.image = Icons.image(for: model.icon)
        menu.removeAllItems()
        if let u = model.unavailable {
            add(u.statusText)
            menu.addItem(.separator())
            add(u.actionTitle) { [weak self] in self?.run(u.action) }
        } else {
            for row in model.tunnels {
                var title = row.name
                if row.warn { title += " ⚠" }
                if row.startsOnResume { title += " — запустится после возобновления" }
                let name = row.name
                let enable = !row.checked
                let mi = add(title, enabled: row.enabled) { [weak self] in
                    self?.toggle(name, on: enable)
                }
                mi.state = row.checked ? .on : .off
                if row.dimmed { mi.onStateImage = Self.dimmedCheck }
            }
            if model.tunnels.isEmpty { add("Нет туннелей") }
            if let p = model.problem {
                menu.addItem(.separator())
                add("⚠ " + p.text)
            }
            menu.addItem(.separator())
            if let title = model.pauseTitle {
                add(title, enabled: model.pauseEnabled) { [weak self] in self?.togglePause() }
            }
        }
        if let errorText {
            menu.addItem(.separator())
            add(errorText)
        }
        menu.addItem(.separator())
        if model.unavailable == nil { add("Открыть Wgplex…") }
        add("Выход", enabled: true) { NSApp.terminate(nil) }
    }

    private static let dimmedCheck: NSImage? = {
        let img = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
        return img?.withSymbolConfiguration(.init(paletteColors: [.tertiaryLabelColor]))
    }()

    /// Adds an item; without an action (or with `enabled: false`) it is inactive.
    @discardableResult
    private func add(
        _ title: String, enabled: Bool = false, action: (@MainActor () -> Void)? = nil
    ) -> NSMenuItem {
        let mi = ActionItem(title: title, handler: action)
        mi.isEnabled = enabled && action != nil
        menu.addItem(mi)
        return mi
    }

    private func run(_ action: UnavailableAction) {
        switch action {
        case .howToInstall:
            NSWorkspace.shared.open(Self.installURL)
        case .copyCommand(let lines):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        }
    }

    private func toggle(_ name: String, on: Bool) {
        let paused = model.paused
        Task {
            let failure = await poller.perform { client in
                if on {
                    _ = try await client.enable(name)
                } else {
                    try await client.disable(name)
                }
            }
            // Remember the tunnel while paused; the status does not carry it.
            if on && paused && failure == nil { startsOnResume.insert(name) } else if !on { startsOnResume.remove(name) }
            if let failure { show(failure) }
        }
    }

    private func togglePause() {
        let resuming = model.paused
        Task {
            let failure = await poller.perform { client in
                if resuming { try await client.resume() } else { try await client.pause() }
            }
            if resuming && failure == nil { startsOnResume = [] }
            if let failure { show(failure) }
        }
    }

    private func show(_ text: String) {
        errorText = text
        rebuild()
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        poller.setMenuOpen(true)
        poller.poll()
    }

    func menuDidClose(_ menu: NSMenu) {
        poller.setMenuOpen(false)
    }
}

/// Menu item that runs a closure.
@MainActor
private final class ActionItem: NSMenuItem {
    private let handler: (@MainActor () -> Void)?

    init(title: String, handler: (@MainActor () -> Void)?) {
        self.handler = handler
        super.init(title: title, action: handler == nil ? nil : #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func fire() { handler?() }
}
