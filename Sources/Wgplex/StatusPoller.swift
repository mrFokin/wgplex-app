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

    /// One `status.get`; skipped while another one is in flight.
    func poll() {
        guard !inFlight else { return }
        inFlight = true
        Task { [weak self] in
            let state = await Self.locate()
            guard let self else { return }
            self.inFlight = false
            self.onState?(state)
        }
    }

    /// Runs `body` with a client on the live socket, then polls at once.
    /// Returns an error text for the menu, or nil.
    func perform(_ body: @escaping @Sendable (Client) async throws -> Void) async -> String? {
        var failure: String?
        if let path = Self.socketPath() {
            do {
                try await body(Client(path: path))
            } catch {
                failure = actionErrorText(error)
            }
        } else {
            failure = "Демон недоступен"
        }
        poll()
        return failure
    }

    private nonisolated static func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    private nonisolated static func socketPath() -> String? {
        Engine.prefixes.map(Engine.socketPath(prefix:)).first(where: exists)
    }

    private nonisolated static func locate() async -> EngineState {
        await Engine.locate(
            fileExists: { exists($0) },
            status: { try await Client(path: $0).status() })
    }
}
