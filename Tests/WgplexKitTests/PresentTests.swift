import XCTest

@testable import WgplexKit

final class PresentTests: XCTestCase {
    private func tunnel(
        _ name: String, enabled: Bool = true, state: TunnelState = .up
    ) -> TunnelStatus {
        TunnelStatus(name: name, enabled: enabled, state: state)
    }

    private func model(_ status: Status, resume: Set<String> = []) -> MenuModel {
        MenuModel.make(from: .ready(status), startsOnResume: resume)
    }

    // design 4: icon comes from status.icon, unknown becomes warn
    func testIconMapping() {
        let cases: [(Icon, MenuIcon)] = [
            (.off, .off), (.on, .on), (.warn, .warn), (.paused, .paused),
            (.unknown("future"), .warn),
        ]
        for (icon, want) in cases {
            XCTAssertEqual(model(Status(icon: icon)).icon, want, "\(icon)")
        }
    }

    // design 4: check mark, warning mark, order of rows
    func testTunnelRows() {
        let cases: [(TunnelStatus, Bool, Bool)] = [  // checked, warn
            (tunnel("a", enabled: false, state: .off), false, false),
            (tunnel("a", state: .up), true, false),
            (tunnel("a", state: .starting), true, false),
            (tunnel("a", state: .dead), true, true),
            (tunnel("a", state: .error), true, true),
            (tunnel("a", enabled: false, state: .dead), false, false),
        ]
        for (t, checked, warn) in cases {
            let rows = model(Status(canControl: true, tunnels: [t])).tunnels
            XCTAssertEqual(rows.count, 1)
            XCTAssertEqual(rows[0].checked, checked, "\(t)")
            XCTAssertEqual(rows[0].warn, warn, "\(t)")
            XCTAssertTrue(rows[0].enabled)
            XCTAssertFalse(rows[0].dimmed)
            XCTAssertFalse(rows[0].startsOnResume)
        }
        let st = Status(tunnels: [tunnel("nl"), tunnel("de"), tunnel("work", enabled: false, state: .off)])
        XCTAssertEqual(model(st).tunnels.map(\.name), ["nl", "de", "work"])
    }

    // design 4: paused -> gray check marks, "Возобновить"
    func testPausedDimsAndTitle() {
        let st = Status(
            canControl: true, paused: true, icon: .paused,
            tunnels: [tunnel("a", state: .off), tunnel("b", enabled: false, state: .off)])
        let m = model(st)
        XCTAssertTrue(m.paused)
        XCTAssertEqual(m.pauseTitle, "Возобновить")
        XCTAssertTrue(m.pauseEnabled)
        XCTAssertEqual(m.tunnels.map(\.dimmed), [true, false])
        XCTAssertEqual(m.tunnels.map(\.checked), [true, false])
        // an enabled tunnel stopped by the pause is not a warning
        XCTAssertEqual(m.tunnels.map(\.warn), [false, false])
    }

    func testRunningTitle() {
        let m = model(Status(canControl: true))
        XCTAssertFalse(m.paused)
        XCTAssertEqual(m.pauseTitle, "Приостановить")
        XCTAssertTrue(m.pauseEnabled)
        XCTAssertNil(m.unavailable)
    }

    // design 4: starts_on_resume only while paused and only for named tunnels
    func testStartsOnResume() {
        let tunnels = [tunnel("a", state: .off), tunnel("b", state: .off)]
        let paused = model(Status(canControl: true, paused: true, tunnels: tunnels), resume: ["a"])
        XCTAssertEqual(paused.tunnels.map(\.startsOnResume), [true, false])

        let running = model(
            Status(canControl: true, paused: false, tunnels: [tunnel("a"), tunnel("b")]), resume: ["a"])
        XCTAssertEqual(running.tunnels.map(\.startsOnResume), [false, false])

        let none = model(Status(canControl: true, paused: true, tunnels: tunnels))
        XCTAssertEqual(none.tunnels.map(\.startsOnResume), [false, false])
    }

    // design 4: can_control false -> rows and pause inactive
    func testCannotControl() {
        let st = Status(canControl: false, tunnels: [tunnel("a"), tunnel("b", enabled: false, state: .off)])
        let m = model(st)
        XCTAssertEqual(m.tunnels.map(\.enabled), [false, false])
        XCTAssertFalse(m.pauseEnabled)
        XCTAssertEqual(m.pauseTitle, "Приостановить")
        XCTAssertEqual(m.tunnels.map(\.checked), [true, false])
    }

    // design 4: no problem
    func testNoProblem() {
        let st = Status(
            canControl: true, tunnels: [tunnel("a")],
            rules: [RuleStatus(index: 0, services: ["x"], via: ["a"], tunnel: "a")])
        XCTAssertNil(model(st).problem)
    }

    // design 4: rule in fallback or degraded -> problem with service name, target rule(index)
    func testRuleProblem() {
        let cases: [RuleStatus] = [
            RuleStatus(index: 3, services: ["youtube"], via: ["a"], inFallback: true, degraded: true, reason: .dead),
            RuleStatus(
                index: 3, services: ["youtube"], via: ["a", "b"], tunnel: "b", inFallback: false,
                degraded: true, reason: .dead),
            RuleStatus(index: 3, services: ["youtube"], via: ["a"], inFallback: true),
        ]
        for rule in cases {
            let p = model(Status(canControl: true, tunnels: [tunnel("a")], rules: [rule])).problem
            XCTAssertEqual(p?.target, .rule(3), "\(rule)")
            XCTAssertTrue(p?.text.contains("youtube") ?? false, "\(String(describing: p))")
        }
    }

    // design 4: dead or failed enabled tunnel -> problem, target tunnel(name)
    func testTunnelProblem() {
        for state in [TunnelState.dead, .error] {
            let st = Status(canControl: true, tunnels: [tunnel("ok"), tunnel("de", state: state)])
            let p = model(st).problem
            XCTAssertEqual(p?.target, .tunnel("de"))
            XCTAssertTrue(p?.text.contains("de") ?? false)
        }
        // a disabled dead tunnel is not a problem
        let st = Status(canControl: true, tunnels: [tunnel("de", enabled: false, state: .dead)])
        XCTAssertNil(model(st).problem)
    }

    // design 4: priority config > rule > tunnel
    func testProblemPriority() {
        let rule = RuleStatus(index: 1, services: ["youtube"], via: ["de"], inFallback: true, degraded: true)
        let tunnels = [tunnel("de", state: .dead)]

        let all = model(Status(canControl: true, configErrorCount: 1, tunnels: tunnels, rules: [rule]))
        XCTAssertEqual(all.problem?.target, .config)

        // redacted caller: only the count is known
        let redacted = model(
            Status(canControl: false, configErrors: [], configErrorCount: 2, tunnels: tunnels, rules: [rule]))
        XCTAssertEqual(redacted.problem?.target, .config)

        let ruleAndTunnel = model(Status(canControl: true, tunnels: tunnels, rules: [rule]))
        XCTAssertEqual(ruleAndTunnel.problem?.target, .rule(1))

        let tunnelOnly = model(Status(canControl: true, tunnels: tunnels))
        XCTAssertEqual(tunnelOnly.problem?.target, .tunnel("de"))
    }

    // design 3: not installed
    func testNotInstalled() {
        let m = MenuModel.make(from: .notInstalled)
        XCTAssertEqual(m.icon, .unavailable)
        XCTAssertTrue(m.tunnels.isEmpty)
        XCTAssertNil(m.problem)
        XCTAssertNil(m.pauseTitle)
        XCTAssertEqual(m.unavailable?.statusText, "wgplex не установлен")
        XCTAssertEqual(m.unavailable?.actionTitle, "Как установить…")
        XCTAssertEqual(m.unavailable?.action, .howToInstall)
    }

    // design 3: binary present, daemon not answering
    func testNotRunning() {
        let m = MenuModel.make(from: .notRunning)
        XCTAssertEqual(m.icon, .unavailable)
        XCTAssertTrue(m.tunnels.isEmpty)
        XCTAssertNil(m.problem)
        XCTAssertNil(m.pauseTitle)
        XCTAssertEqual(m.unavailable?.statusText, "Демон не запущен")
        XCTAssertEqual(m.unavailable?.actionTitle, "Копировать команду запуска")
        XCTAssertEqual(
            m.unavailable?.action,
            .copyCommand(["sudo brew services start --sudo-service-user=root wgplex"]))
    }

    // design 3: api_version too low
    func testOutdated() {
        let m = MenuModel.make(from: .outdated(apiVersion: 0))
        XCTAssertEqual(m.icon, .unavailable)
        XCTAssertTrue(m.tunnels.isEmpty)
        XCTAssertNil(m.problem)
        XCTAssertNil(m.pauseTitle)
        XCTAssertEqual(m.unavailable?.statusText, "Обновите wgplex")
        XCTAssertEqual(m.unavailable?.actionTitle, "Копировать команды обновления")
        XCTAssertEqual(
            m.unavailable?.action,
            .copyCommand([
                "brew upgrade wgplex",
                "sudo brew services restart --sudo-service-user=root wgplex",
            ]))
    }
}
