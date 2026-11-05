import XCTest

@testable import WgplexKit

final class NotificationPlannerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func tunnel(_ name: String, enabled: Bool = true, state: TunnelState = .up) -> TunnelStatus {
        TunnelStatus(name: name, enabled: enabled, state: state)
    }

    private func ready(
        tunnels: [TunnelStatus] = [], rules: [RuleStatus] = [], paused: Bool = false,
        errors: Int = 0, canControl: Bool = true
    ) -> EngineState {
        .ready(
            Status(
                canControl: canControl, paused: paused, configErrorCount: errors, tunnels: tunnels, rules: rules))
    }

    /// Healthy state: nl up, rule goes through nl.
    private var healthy: EngineState {
        ready(
            tunnels: [tunnel("nl"), tunnel("de")],
            rules: [RuleStatus(index: 0, services: ["youtube", "ai"], via: ["nl", "de"], tunnel: "nl")])
    }

    /// nl dead, rule moved to the backup de with reason dead.
    private var nlDeadOnBackup: EngineState {
        ready(
            tunnels: [tunnel("nl", state: .dead), tunnel("de")],
            rules: [
                RuleStatus(
                    index: 0, services: ["youtube", "ai"], via: ["nl", "de"], tunnel: "de", degraded: true,
                    reason: .dead)
            ])
    }

    private func plan(
        _ planner: inout NotificationPlanner, _ prev: EngineState?, _ next: EngineState, at: Date? = nil
    ) -> [AppNotification] {
        planner.plan(prev: prev, next: next, now: at ?? t0)
    }

    // design 7: first poll after start only remembers, an old problem is not announced
    func testFirstPollIsSilent() {
        for state in [nlDeadOnBackup, ready(errors: 3), .notRunning, healthy] {
            var p = NotificationPlanner()
            XCTAssertEqual(plan(&p, nil, state), [], "\(state)")
        }
    }

    // design 7: tunnel died, rules moved to backup
    func testTunnelDeadOnBackup() {
        var p = NotificationPlanner()
        let n = plan(&p, healthy, nlDeadOnBackup)
        XCTAssertEqual(n.count, 1)
        XCTAssertEqual(n.first?.title, "nl не отвечает")
        XCTAssertEqual(n.first?.body, "youtube, ai → de")
        XCTAssertEqual(n.first?.target, .tunnel("nl"))
    }

    // design 7: tunnel failed to come up (error) with rules in fallback
    func testTunnelErrorWithRulesInFallback() {
        let next = ready(
            tunnels: [tunnel("nl", state: .error)],
            rules: [
                RuleStatus(
                    index: 0, services: ["youtube"], via: ["nl"], inFallback: true, degraded: true, reason: .dead)
            ])
        var p = NotificationPlanner()
        let n = plan(&p, healthy, next)
        XCTAssertEqual(n.count, 1)
        XCTAssertEqual(n.first?.title, "nl не отвечает")
        XCTAssertEqual(n.first?.target, .tunnel("nl"))
    }

    // design 7: recovery
    func testTunnelRecovery() {
        var p = NotificationPlanner()
        let n = plan(&p, nlDeadOnBackup, healthy)
        XCTAssertEqual(n.count, 1)
        XCTAssertEqual(n.first?.title, "nl снова работает")
        XCTAssertEqual(n.first?.target, .tunnel("nl"))
    }

    // design 7: still dead, nothing changed -> no repeat
    func testNoRepeatWhileStillDead() {
        var p = NotificationPlanner()
        XCTAssertEqual(plan(&p, nlDeadOnBackup, nlDeadOnBackup), [])
    }

    // design 7: no notification for intentional rule states
    func testRulesWithReasonDisabledOrPausedAreSilent() {
        for reason in [RuleReason.disabled, .paused] {
            let next = ready(
                tunnels: [tunnel("nl", enabled: false, state: .off)],
                rules: [
                    RuleStatus(
                        index: 0, services: ["a"], via: ["nl"], inFallback: true, degraded: true, reason: reason)
                ])
            var p = NotificationPlanner()
            XCTAssertEqual(plan(&p, healthy, next), [], "\(reason)")
        }
    }

    // design 7: pause is not noticed (and resume too)
    func testPauseAndResumeAreSilent() {
        let paused = ready(
            tunnels: [tunnel("nl", state: .off)],
            rules: [
                RuleStatus(
                    index: 0, services: ["youtube"], via: ["nl"], inFallback: true, degraded: true, reason: .paused)
            ], paused: true)
        var p = NotificationPlanner()
        XCTAssertEqual(plan(&p, healthy, paused), [])
        XCTAssertEqual(plan(&p, paused, healthy), [])
    }

    // design 7: toggling a tunnel (by the user, another user or CLI) is not noticed
    func testEnableDisableIsSilent() {
        let off = ready(
            tunnels: [tunnel("nl", enabled: false, state: .off), tunnel("de")],
            rules: [RuleStatus(index: 0, services: ["youtube"], via: ["nl", "de"], tunnel: "de")])
        var p = NotificationPlanner()
        XCTAssertEqual(plan(&p, healthy, off), [])
        XCTAssertEqual(plan(&p, off, healthy), [])
    }

    // design 7: a disabled tunnel in state off is never "dead"
    func testDisabledTunnelNotReportedDead() {
        let next = ready(tunnels: [tunnel("nl", enabled: false, state: .error)])
        var p = NotificationPlanner()
        XCTAssertEqual(plan(&p, healthy, next), [])
    }

    // design 7: config error on reload
    func testConfigErrorOnReload() {
        var p = NotificationPlanner()
        let n = plan(&p, ready(errors: 0), ready(errors: 2))
        XCTAssertEqual(n.count, 1)
        XCTAssertTrue(n.first?.title.hasPrefix("Изменения конфига не применены") == true, "\(n)")
        XCTAssertEqual(n.first?.target, .config)
        let all = (n.first?.title ?? "") + (n.first?.body ?? "")
        XCTAssertTrue(all.contains("2"), "error count in the text: \(all)")
    }

    // design 7: count grew while the daemon was already ready (1 -> 3)
    func testConfigErrorCountGrew() {
        var p = NotificationPlanner()
        let n = plan(&p, ready(errors: 1), ready(errors: 3))
        XCTAssertEqual(n.count, 1)
        XCTAssertEqual(n.first?.target, .config)
    }

    // design 7: same or lower count is silent
    func testConfigErrorCountNotGrown() {
        var p = NotificationPlanner()
        XCTAssertEqual(plan(&p, ready(errors: 2), ready(errors: 2)), [])
        XCTAssertEqual(plan(&p, ready(errors: 2), ready(errors: 1)), [])
        XCTAssertEqual(plan(&p, ready(errors: 2), ready(errors: 0)), [])
    }

    // design 7: config error at daemon start
    func testConfigErrorAtStart() {
        var p = NotificationPlanner()
        let n = plan(&p, .notRunning, ready(errors: 1))
        XCTAssertEqual(n.count, 1)
        XCTAssertEqual(n.first?.title, "wgplex запущен без туннелей: конфиг с ошибками")
        XCTAssertEqual(n.first?.target, .config)
    }

    // design 7 + api: can_control false still has config_error_count
    func testConfigErrorForCallerWithoutControl() {
        var p = NotificationPlanner()
        let n = plan(&p, ready(errors: 0, canControl: false), ready(errors: 2, canControl: false))
        XCTAssertEqual(n.count, 1)
        XCTAssertEqual(n.first?.target, .config)
    }

    // design 7: daemon disappeared / came back
    func testDaemonLostAndBack() {
        var p = NotificationPlanner()
        let lost = plan(&p, healthy, .notRunning)
        XCTAssertEqual(lost.count, 1)
        XCTAssertEqual(lost.first?.title, "wgplex не работает")
        XCTAssertEqual(lost.first?.target, .daemon)
        let back = plan(&p, .notRunning, healthy, at: t0.addingTimeInterval(10))
        XCTAssertEqual(back.count, 1)
        XCTAssertEqual(back.first?.title, "wgplex снова работает")
        XCTAssertEqual(back.first?.target, .daemon)
    }

    // design 7: still not running -> no repeat
    func testDaemonStillDownIsSilent() {
        var p = NotificationPlanner()
        XCTAssertEqual(plan(&p, .notRunning, .notRunning), [])
    }

    // design 7: notInstalled / outdated are silent in both directions
    func testNotInstalledAndOutdatedAreSilent() {
        let states: [EngineState] = [.notInstalled, .outdated(apiVersion: 0)]
        for s in states {
            var p = NotificationPlanner()
            XCTAssertEqual(plan(&p, healthy, s), [], "ready -> \(s)")
            XCTAssertEqual(plan(&p, s, healthy), [], "\(s) -> ready")
        }
    }

    // design 7: events of one poll -> one notification
    func testEventsOfOnePollMerge() {
        let prev = ready(
            tunnels: [tunnel("nl"), tunnel("de")],
            rules: [RuleStatus(index: 0, services: ["youtube", "ai"], via: ["nl", "de"], tunnel: "nl")],
            errors: 0)
        let next = ready(
            tunnels: [tunnel("nl", state: .dead), tunnel("de")],
            rules: [
                RuleStatus(
                    index: 0, services: ["youtube", "ai"], via: ["nl", "de"], tunnel: "de", degraded: true,
                    reason: .dead)
            ], errors: 2)
        var p = NotificationPlanner()
        let n = plan(&p, prev, next)
        XCTAssertEqual(n.count, 1, "\(n)")
        XCTAssertTrue([ProblemTarget.tunnel("nl"), .config].contains(n[0].target))
    }

    func testTwoTunnelsDeadInOnePollMerge() {
        let prev = ready(tunnels: [tunnel("nl"), tunnel("de")])
        let next = ready(
            tunnels: [tunnel("nl", state: .dead), tunnel("de", state: .dead)],
            rules: [
                RuleStatus(index: 0, services: ["a"], via: ["nl", "de"], inFallback: true, degraded: true, reason: .dead)
            ])
        var p = NotificationPlanner()
        XCTAssertEqual(plan(&p, prev, next).count, 1)
    }

    // design 7: flapping tunnel — at most once per 5 minutes
    func testFlapIntervalConstant() {
        XCTAssertEqual(NotificationPlanner.flapInterval, 300)
    }

    func testFlappingTunnelNotifiedOncePerFiveMinutes() {
        var p = NotificationPlanner()
        XCTAssertEqual(plan(&p, healthy, nlDeadOnBackup, at: t0).count, 1)
        // recovery after 10 s: same tunnel within 5 min -> silent
        XCTAssertEqual(plan(&p, nlDeadOnBackup, healthy, at: t0.addingTimeInterval(10)), [])
        // dies again after 60 s: still silent
        XCTAssertEqual(plan(&p, healthy, nlDeadOnBackup, at: t0.addingTimeInterval(70)), [])
        // just under 5 minutes since the last notification
        XCTAssertEqual(plan(&p, nlDeadOnBackup, healthy, at: t0.addingTimeInterval(299)), [])
        // later than 5 minutes after the last notification: notifies again
        let n = plan(&p, healthy, nlDeadOnBackup, at: t0.addingTimeInterval(301))
        XCTAssertEqual(n.count, 1)
        XCTAssertEqual(n.first?.title, "nl не отвечает")
    }

    func testSilencedPollDoesNotExtendWindow() {
        var p = NotificationPlanner()
        _ = plan(&p, healthy, nlDeadOnBackup, at: t0)
        // silent event at +200 s must not move lastNotified
        _ = plan(&p, nlDeadOnBackup, healthy, at: t0.addingTimeInterval(200))
        XCTAssertEqual(p.lastNotified["nl"], t0)
        XCTAssertEqual(plan(&p, healthy, nlDeadOnBackup, at: t0.addingTimeInterval(301)).count, 1)
    }

    func testFlapWindowIsPerTunnel() {
        var p = NotificationPlanner()
        _ = plan(&p, healthy, nlDeadOnBackup, at: t0)
        let deDead = ready(
            tunnels: [tunnel("nl"), tunnel("de", state: .dead)],
            rules: [
                RuleStatus(index: 0, services: ["a"], via: ["de"], inFallback: true, degraded: true, reason: .dead)
            ])
        let n = plan(&p, healthy, deDead, at: t0.addingTimeInterval(30))
        XCTAssertEqual(n.count, 1)
        XCTAssertEqual(n.first?.title, "de не отвечает")
    }

    // design 7: the planner state is only updated when a notification is produced
    func testLastNotifiedUpdatedOnlyWithNotification() {
        var p = NotificationPlanner()
        _ = plan(&p, nil, nlDeadOnBackup)
        _ = plan(&p, healthy, healthy)
        XCTAssertTrue(p.lastNotified.isEmpty)
        _ = plan(&p, healthy, nlDeadOnBackup, at: t0)
        XCTAssertEqual(p.lastNotified["nl"], t0)
    }

    // design 2/7: update notification
    func testUpdateNotification() {
        let u = UpdateInfo(version: "1.3.0", url: "https://github.com/mrFokin/wgplex-app/releases/tag/v1.3.0")
        let n = NotificationPlanner.notification(for: u)
        XCTAssertEqual(n.title, "Доступна Wgplex 1.3.0")
        XCTAssertTrue(n.body.contains("brew upgrade --cask wgplex-app"), n.body)
        XCTAssertEqual(n.target, .daemon)
    }
}
