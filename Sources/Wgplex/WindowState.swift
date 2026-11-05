import Foundation
import WgplexKit

/// Sidebar sections of the window (design 5).
enum WindowSection: String, CaseIterable, Identifiable {
    case tunnels, rules, diagnostics, logs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tunnels: return "Туннели"
        case .rules: return "Правила"
        case .diagnostics: return "Диагностика"
        case .logs: return "Логи"
        }
    }

    var symbol: String {
        switch self {
        case .tunnels: return "lock.shield"
        case .rules: return "list.bullet"
        case .diagnostics: return "stethoscope"
        case .logs: return "doc.text"
        }
    }
}

/// What the window shows and does. Fed with `EngineState` by `StatusController`;
/// actions go through the same `StatusPoller` as the menu.
@MainActor
final class WindowState: ObservableObject {
    /// Nil until the first poll answers.
    @Published var state: EngineState?
    @Published var section: WindowSection = .tunnels
    @Published var selectedTunnel: String?
    @Published var selectedRule: Int?
    /// Action error or reload result, shown in the banner area.
    @Published var message: Message?
    /// An action is running.
    @Published var busy = false
    /// A newer release, shown as the lowest-priority banner.
    @Published var update: UpdateInfo?
    /// Called after the user's "Перечитать конфиг" RPC finished (its result is not notified).
    var onReload: (() -> Void)?

    struct Message: Equatable {
        var text: String
        var isError: Bool
    }

    let poller: StatusPoller

    init(poller: StatusPoller) {
        self.poller = poller
    }

    var model: WindowModel? {
        state.map { WindowModel.make(from: $0, update: update, startsOnResume: poller.startsOnResume) }
    }

    var status: Status? {
        if case .ready(let s) = state { return s }
        return nil
    }

    func update(_ new: EngineState) {
        state = new
    }

    /// Opens the section a problem or banner leads to; the daemon target stays put.
    func navigate(to target: ProblemTarget) {
        switch target {
        case .rule(let index):
            section = .rules
            selectedRule = index
        case .tunnel(let name):
            section = .tunnels
            selectedTunnel = name
        case .config:
            section = .tunnels
        case .daemon:
            // Stays put: also the target of the update banner, which sits at the top of every section.
            break
        }
    }

    func toggle(_ name: String, on: Bool) {
        run { poller in
            let (result, failure) = await poller.perform { client -> EnableResult? in
                if on { return try await client.enable(name) }
                try await client.disable(name)
                return nil
            }
            if failure == nil {
                poller.noteEnabled(name, startsOnResume: on && result??.startsOnResume == true)
            }
            return failure.map { Message(text: $0, isError: true) }
        }
    }

    func togglePause() {
        let resuming = status?.paused ?? false
        run { poller in
            let (_, failure) = await poller.perform { client -> Bool in
                if resuming { try await client.resume() } else { try await client.pause() }
                return true
            }
            if failure == nil, resuming { poller.clearStartsOnResume() }
            return failure.map { Message(text: $0, isError: true) }
        }
    }

    func disableAll() {
        run { poller in
            let (_, failure) = await poller.perform { client -> Bool in
                try await client.disableAll()
                return true
            }
            return failure.map { Message(text: $0, isError: true) }
        }
    }

    func reload() {
        run { [weak self] poller in
            let (result, failure) = await poller.perform { try await $0.reload() }
            self?.onReload?()
            if let failure { return Message(text: failure, isError: true) }
            guard let result else { return nil }
            if result.tunnels.isEmpty { return Message(text: "Применено", isError: false) }
            let names = result.tunnels.map(\.name).joined(separator: ", ")
            return Message(text: "Применено, не поднялись туннели: \(names)", isError: true)
        }
    }

    private var messageTask: Task<Void, Never>?

    /// Shows the outcome; it disappears after 5 s.
    private func show(_ outcome: Message?) {
        messageTask?.cancel()
        message = outcome
        guard outcome != nil else { return }
        messageTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if !Task.isCancelled { self?.message = nil }
        }
    }

    /// Runs one action at a time; its outcome replaces the message.
    private func run(_ body: @escaping @MainActor (StatusPoller) async -> Message?) {
        guard !busy else { return }
        busy = true
        show(nil)
        Task {
            let outcome = await body(poller)
            show(outcome)
            busy = false
        }
    }
}
