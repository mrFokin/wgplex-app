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
    /// Nil until the first poll answers.
    private var state: EngineState?
    private var model: MenuModel?
    private var rendered: Rendered?
    private var errorTask: Task<Void, Never>?
    /// Tunnels enabled while paused; kept until resume or a status without pause.
    private var startsOnResume: Set<String> = []
    /// Action error shown for 5 s, until the menu closes or the next action.
    private var errorText: String?

    private struct Rendered: Equatable {
        var model: MenuModel?
        var errorText: String?
    }

    override init() {
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        item.button?.image = Icons.image(for: .off)
        rebuild()
        poller.onState = { [weak self] in self?.apply($0) }
        poller.start()
    }

    private func apply(_ new: EngineState) {
        state = new
        if case .ready(let s) = new, s.paused {} else { startsOnResume = [] }
        rebuild()
    }

    /// Rebuilds the items in place when the content changed; works while the menu is open.
    private func rebuild() {
        let new = state.map { MenuModel.make(from: $0, startsOnResume: startsOnResume) }
        let now = Rendered(model: new, errorText: errorText)
        guard now != rendered else { return }
        rendered = now
        model = new
        item.button?.image = Icons.image(for: new?.icon ?? .off)
        menu.removeAllItems()
        guard let model = new else {
            add("Загрузка…")
            menu.addItem(.separator())
            add("Выход") { NSApp.terminate(nil) }
            return
        }
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
        add("Выход") { NSApp.terminate(nil) }
    }

    private static let dimmedCheck: NSImage? = {
        let img = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
        return img?.withSymbolConfiguration(.init(paletteColors: [.tertiaryLabelColor]))
    }()

    /// Adds an item; without an action (or with `enabled: false`) it is inactive.
    @discardableResult
    private func add(
        _ title: String, enabled: Bool = true, action: (@MainActor () -> Void)? = nil
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
        clearError()
        Task {
            let (result, failure) = await poller.perform { client -> EnableResult? in
                if on { return try await client.enable(name) }
                try await client.disable(name)
                return nil
            }
            if let failure {
                show(failure)
            } else if on, result??.startsOnResume == true {
                startsOnResume.insert(name)
            } else {
                startsOnResume.remove(name)
            }
        }
    }

    private func togglePause() {
        let resuming = model?.paused ?? false
        clearError()
        Task {
            let (_, failure) = await poller.perform { client -> Bool in
                if resuming { try await client.resume() } else { try await client.pause() }
                return true
            }
            if let failure {
                show(failure)
            } else if resuming {
                startsOnResume = []
            }
        }
    }

    private func show(_ text: String) {
        errorText = text
        rebuild()
        errorTask?.cancel()
        errorTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if !Task.isCancelled { self?.clearError() }
        }
    }

    private func clearError() {
        errorTask?.cancel()
        errorTask = nil
        guard errorText != nil else { return }
        errorText = nil
        rebuild()
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        poller.setMenuOpen(true)
        poller.poll()
    }

    func menuDidClose(_ menu: NSMenu) {
        poller.setMenuOpen(false)
        clearError()
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
