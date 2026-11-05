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
    private lazy var window = WindowController(poller: poller)
    private let settings = Settings()
    private let loginItem = LoginItem()
    private let notifier: Notifier
    private lazy var updater = Updater(settings: settings)
    private lazy var settingsWindow = SettingsController(
        settings: settings, loginItem: loginItem,
        onNotificationsOn: { [weak self] in self?.notifier.requestAuthorization() },
        onUpdatesChanged: { [weak self] in self?.updater.settingsChanged() })
    private var planner = NotificationPlanner()
    /// Previous poll for the planner; nil until the first one.
    private var prevState: EngineState?
    /// Nil until the first poll answers.
    private var state: EngineState?
    private var model: MenuModel?
    private var rendered: Rendered?
    private var errorTask: Task<Void, Never>?
    /// Action error shown for 5 s, until the menu closes or the next action.
    private var errorText: String?

    private struct Rendered: Equatable {
        var model: MenuModel?
        var errorText: String?
    }

    init(notifier: Notifier) {
        self.notifier = notifier
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        item.button?.image = Icons.image(for: .off)
        rebuild()
        poller.onState = { [weak self] in self?.apply($0) }
        notifier.onOpen = { [weak self] in self?.openWindow($0) }
        window.state.onReload = { [weak self] in self?.planner.noteOwnReload() }
        updater.onUpdate = { [weak self] in self?.window.state.update = $0 }
        updater.onNotify = { [weak self] in
            guard let self else { return }
            self.notifier.post(NotificationPlanner.notification(for: $0))
        }
        poller.start()
        updater.start()
        DispatchQueue.main.async { [weak self] in self?.firstRun() }
    }

    func openSettings() { settingsWindow.show() }

    /// One question on the very first launch: login item and notification permission.
    /// Without an app bundle neither exists, so nothing is asked and the flag stays unset.
    private func firstRun() {
        guard Settings.hasBundle, !settings.firstRunDone else { return }
        settings.firstRunDone = true
        let alert = NSAlert()
        alert.messageText = "Запускать Wgplex при входе?"
        alert.informativeText = "Это можно изменить в настройках."
        alert.addButton(withTitle: "Запускать")
        alert.addButton(withTitle: "Не нужно")
        NSApp.activate(ignoringOtherApps: true)
        let launch = alert.runModal() == .alertFirstButtonReturn
        if launch {
            loginItem.set(true)
            if loginItem.error != nil { openSettings() }
        }
        notifier.requestAuthorization()
    }

    private func apply(_ new: EngineState) {
        let now = Date()
        // The planner always runs so its state stays current; the setting only gates display.
        let planned = planner.plan(prev: prevState, next: new, now: now)
        prevState = new
        if settings.notifications {
            for n in planned { notifier.post(n) }
        }
        state = new
        window.state.update(new)
        rebuild()
    }

    /// Rebuilds the items in place when the content changed; works while the menu is open.
    private func rebuild() {
        let new = state.map { MenuModel.make(from: $0, startsOnResume: poller.startsOnResume) }
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
                let target = p.target
                add("⚠ " + p.text) { [weak self] in self?.openWindow(target) }
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
        add("Открыть Wgplex…") { [weak self] in self?.openWindow(nil) }
        add("Настройки…") { [weak self] in self?.openSettings() }
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

    /// Opens the window; a problem target picks the section.
    private func openWindow(_ target: ProblemTarget?) {
        if let target { window.state.navigate(to: target) }
        window.show()
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
            } else {
                poller.noteEnabled(name, startsOnResume: on && result??.startsOnResume == true)
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
                poller.clearStartsOnResume()
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
