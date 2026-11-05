import Foundation
import WgplexKit

/// Polls `status.get` and runs engine actions. Everything runs on the main
/// actor; only the socket I/O is awaited off it.
@MainActor
final class StatusPoller {
    /// Called on every fresh state.
    var onState: ((EngineState) -> Void)?

    private var timer: Timer?
    private var inFlight = false
    private var repollPending = false
    /// Socket that answered the last successful poll; actions use it.
    private var lastSocketPath: String?

    /// Starts background polling (10 s) and polls once.
    func start() {
        setInterval(10)
        poll()
    }

    /// 1.5 s while the menu is open, 10 s otherwise.
    func setMenuOpen(_ open: Bool) {
        setInterval(open ? 1.5 : 10)
    }

    private func setInterval(_ value: TimeInterval) {
        timer?.invalidate()
        let t = Timer(timeInterval: value, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// One `status.get`; a call during another one runs once more after it.
    func poll() {
        guard !inFlight else {
            repollPending = true
            return
        }
        inFlight = true
        Task { [weak self] in
            let state = await Self.locate { path in
                await MainActor.run { self?.lastSocketPath = path }
            }
            guard let self else { return }
            self.inFlight = false
            if case .ready = state {} else { self.lastSocketPath = nil }
            self.onState?(state)
            if self.repollPending {
                self.repollPending = false
                self.poll()
            }
        }
    }

    /// Runs `body` with a client on the socket that answered the last poll,
    /// then polls at once. Returns the result and an error text for the menu.
    func perform<T: Sendable>(
        _ body: @escaping @Sendable (Client) async throws -> T
    ) async -> (value: T?, failure: String?) {
        var value: T?
        var failure: String?
        if let path = lastSocketPath {
            do {
                value = try await body(Client(path: path))
            } catch {
                failure = actionErrorText(error)
            }
        } else {
            failure = "Демон недоступен"
        }
        poll()
        return (value, failure)
    }

    private nonisolated static func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    private nonisolated static func locate(
        answered: @escaping @Sendable (String) async -> Void
    ) async -> EngineState {
        await Engine.locate(
            fileExists: { exists($0) },
            status: {
                let status = try await Client(path: $0).status()
                await answered($0)
                return status
            })
    }
}
