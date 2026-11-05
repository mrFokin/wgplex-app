import Foundation

/// Status-item icon (design 4). Drawn by the app; the Kit only picks one.
public enum MenuIcon: Equatable, Sendable {
    /// Outlined shield: everything is off.
    case off
    /// Filled shield: running.
    case on
    /// Shield with "!": a problem (also used for `Icon.unknown`).
    case warn
    /// Shield with pause bars.
    case paused
    /// Engine not installed, not running or outdated: shield with "!".
    case unavailable
}

/// Where a click on the problem row leads in the window (design 4, 5).
public enum ProblemTarget: Equatable, Sendable {
    /// Rule with this `index`.
    case rule(Int)
    /// Tunnel with this name.
    case tunnel(String)
    /// Config errors.
    case config
    /// Daemon unavailable.
    case daemon
}

/// The problem row ("⚠ youtube на резерве").
public struct ProblemRow: Equatable, Sendable {
    /// Display text in Russian, without the "⚠" mark.
    public var text: String
    public var target: ProblemTarget

    public init(text: String, target: ProblemTarget) {
        self.text = text
        self.target = target
    }
}

/// One tunnel row.
public struct TunnelRow: Equatable, Sendable {
    public var name: String
    /// Check mark: the tunnel is enabled.
    public var checked: Bool
    /// "⚠" after the name: enabled but dead or failed to start.
    public var warn: Bool
    /// Gray check mark: the engine is paused.
    public var dimmed: Bool
    /// Clickable; false when `can_control` is false.
    public var enabled: Bool
    /// Add the "запустится после возобновления" note (enabled while paused).
    public var startsOnResume: Bool

    public init(
        name: String, checked: Bool, warn: Bool, dimmed: Bool, enabled: Bool, startsOnResume: Bool
    ) {
        self.name = name
        self.checked = checked
        self.warn = warn
        self.dimmed = dimmed
        self.enabled = enabled
        self.startsOnResume = startsOnResume
    }
}

/// Action offered when the engine is unavailable (design 3).
public enum UnavailableAction: Equatable, Sendable {
    /// "Как установить…": open the install page.
    case howToInstall
    /// Copy these shell commands (one per line) to the pasteboard.
    case copyCommand([String])
}

/// Menu contents for the unavailable states.
public struct UnavailableInfo: Equatable, Sendable {
    /// Status line: "wgplex не установлен", "Демон не запущен", "Обновите wgplex".
    public var statusText: String
    /// Title of the action item: "Как установить…", "Копировать команду запуска",
    /// "Копировать команды обновления".
    public var actionTitle: String
    public var action: UnavailableAction

    public init(statusText: String, actionTitle: String, action: UnavailableAction) {
        self.statusText = statusText
        self.actionTitle = actionTitle
        self.action = action
    }
}

/// Everything the menu shows, computed from `EngineState` (design 4). Pure
/// data, no AppKit.
public struct MenuModel: Equatable, Sendable {
    public var icon: MenuIcon
    /// Tunnel rows in the order of `status.tunnels`; empty when unavailable.
    public var tunnels: [TunnelRow]
    /// First problem by priority: config errors, rule fallback/degraded,
    /// dead or failed enabled tunnel. Nil when there is none or when unavailable.
    public var problem: ProblemRow?
    /// "Приостановить" or "Возобновить"; nil when unavailable.
    public var pauseTitle: String?
    /// The pause item is clickable (`can_control`).
    public var pauseEnabled: Bool
    /// The engine is paused.
    public var paused: Bool
    /// Non-nil when the engine is not ready (no tunnels, pause or problem rows).
    public var unavailable: UnavailableInfo?

    public init(
        icon: MenuIcon, tunnels: [TunnelRow], problem: ProblemRow?, pauseTitle: String?,
        pauseEnabled: Bool, paused: Bool, unavailable: UnavailableInfo?
    ) {
        self.icon = icon
        self.tunnels = tunnels
        self.problem = problem
        self.pauseTitle = pauseTitle
        self.pauseEnabled = pauseEnabled
        self.paused = paused
        self.unavailable = unavailable
    }

    /// Builds the menu model.
    ///
    /// - Parameters:
    ///   - state: engine state from `Engine.locate`.
    ///   - startsOnResume: names of tunnels for which `tunnel.enable` returned
    ///     `starts_on_resume` (the status does not carry it).
    public static func make(from state: EngineState, startsOnResume: Set<String> = []) -> MenuModel {
        func unavailable(_ text: String, _ title: String, _ action: UnavailableAction) -> MenuModel {
            MenuModel(
                icon: .unavailable, tunnels: [], problem: nil, pauseTitle: nil,
                pauseEnabled: false, paused: false,
                unavailable: UnavailableInfo(statusText: text, actionTitle: title, action: action))
        }

        let status: Status
        switch state {
        case .notInstalled:
            return unavailable("wgplex не установлен", "Как установить…", .howToInstall)
        case .notRunning:
            return unavailable(
                "Демон не запущен", "Копировать команду запуска",
                .copyCommand(["sudo brew services start --sudo-service-user=root wgplex"]))
        case .outdated:
            return unavailable(
                "Обновите wgplex", "Копировать команды обновления",
                .copyCommand([
                    "brew upgrade wgplex",
                    "sudo brew services restart --sudo-service-user=root wgplex",
                ]))
        case .ready(let s):
            status = s
        }

        let icon: MenuIcon
        switch status.icon {
        case .off: icon = .off
        case .on: icon = .on
        case .paused: icon = .paused
        case .warn, .unknown: icon = .warn
        }

        let tunnels = status.tunnels.map { t in
            TunnelRow(
                name: t.name, checked: t.enabled,
                warn: !status.paused && t.enabled && (t.state == .dead || t.state == .error),
                dimmed: status.paused && t.enabled, enabled: status.canControl,
                startsOnResume: startsOnResume.contains(t.name) && status.paused)
        }

        return MenuModel(
            icon: icon, tunnels: tunnels, problem: problem(of: status),
            pauseTitle: status.paused ? "Возобновить" : "Приостановить",
            pauseEnabled: status.canControl, paused: status.paused, unavailable: nil)
    }

    /// A rule is a problem when it is degraded or in fallback for a real cause;
    /// `paused` and `disabled` are intentional states.
    private static func isProblem(_ rule: RuleStatus) -> Bool {
        guard rule.inFallback || rule.degraded else { return false }
        switch rule.reason {
        case nil, .dead, .unknown: return true
        case .paused, .disabled: return false
        }
    }

    private static func problem(of status: Status) -> ProblemRow? {
        if status.configErrorCount > 0 {
            return ProblemRow(text: "ошибка конфига", target: .config)
        }
        if let rule = status.rules.first(where: isProblem) {
            var service = rule.services.first ?? "правило \(rule.index)"
            if rule.services.count > 1 { service += " и ещё \(rule.services.count - 1)" }
            // In fallback nothing serves the rule; degraded only: a spare tunnel does.
            let text = rule.inFallback ? "\(service) без туннеля" : "\(service) на резерве"
            return ProblemRow(text: text, target: .rule(rule.index))
        }
        if !status.paused,
            let t = status.tunnels.first(where: { $0.enabled && ($0.state == .dead || $0.state == .error) })
        {
            let text = t.state == .error ? "\(t.name): не поднялся" : "\(t.name): недоступен"
            return ProblemRow(text: text, target: .tunnel(t.name))
        }
        return nil
    }
}
