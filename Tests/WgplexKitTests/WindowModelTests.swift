import XCTest

@testable import WgplexKit

final class WindowModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func tunnel(
        _ name: String, enabled: Bool = true, state: TunnelState = .up, peers: [PeerStatus] = [],
        check: CheckStatus? = nil, interface: String? = nil, addresses: [String] = [],
        routeCount: Int = 0, error: String? = nil, reason: String? = nil
    ) -> TunnelStatus {
        TunnelStatus(
            name: name, enabled: enabled, state: state, error: error, interface: interface,
            addresses: addresses, routeCount: routeCount, peers: peers, reason: reason, check: check)
    }

    private func make(_ status: Status, resume: Set<String> = []) -> WindowModel {
        WindowModel.make(from: .ready(status), startsOnResume: resume, now: now)
    }

    // MARK: formatBytes (fixed format: base 1024, decimal comma, one decimal below 10)

    func testFormatBytes() {
        let kb = 1024, mb = 1024 * 1024, gb = 1024 * 1024 * 1024
        let cases: [(Int, String)] = [
            (0, "0 Б"), (1, "1 Б"), (512, "512 Б"), (1023, "1023 Б"),
            (1024, "1,0 КБ"), (1536, "1,5 КБ"), (10 * kb, "10 КБ"), (100 * kb, "100 КБ"),
            (mb, "1,0 МБ"), (12 * mb, "12 МБ"),
            (gb, "1,0 ГБ"), (Int(1.2 * Double(gb)), "1,2 ГБ"),
        ]
        for (n, want) in cases {
            XCTAssertEqual(WindowModel.formatBytes(n), want, "\(n)")
        }
    }

    // MARK: formatHandshake

    func testFormatHandshake() {
        let cases: [(Int?, String)] = [
            (nil, "нет"), (0, "0 с назад"), (5, "5 с назад"), (59, "59 с назад"),
            (60, "1 мин назад"), (120, "2 мин назад"), (3599, "59 мин назад"),
            (3600, "1 ч назад"), (7200, "2 ч назад"),
        ]
        for (s, want) in cases {
            XCTAssertEqual(WindowModel.formatHandshake(secondsAgo: s), want, "\(String(describing: s))")
        }
    }

    // MARK: banner (design 5; priority per plan A3)

    func testNoBannerWhenNoProblems() {
        let st = Status(
            canControl: true, tunnels: [tunnel("nl")],
            rules: [RuleStatus(index: 0, services: ["a"], via: ["nl"], tunnel: "nl")])
        XCTAssertNil(make(st).banner)
    }

    func testBannerConfigError() {
        let b = make(Status(configErrorCount: 2)).banner
        XCTAssertEqual(b?.kind, .configError)
        XCTAssertEqual(b?.target, .config)
        XCTAssertEqual(b?.text, "ошибка конфига")
    }

    func testBannerDaemonUnavailable() {
        let cases: [(EngineState, String)] = [
            (.notInstalled, "wgplex не установлен"),
            (.notRunning, "Демон не запущен"),
            (.outdated(apiVersion: 0), "Обновите wgplex"),
        ]
        for (state, text) in cases {
            let m = WindowModel.make(from: state, now: now)
            XCTAssertEqual(m.banner, Banner(kind: .daemonUnavailable, text: text, target: .daemon), "\(state)")
        }
    }

    func testBannerPaused() {
        let b = make(Status(paused: true, tunnels: [tunnel("nl")])).banner
        XCTAssertEqual(b?.kind, .paused)
        XCTAssertEqual(b?.text, "Приостановлено")
    }

    func testBannerRuleOnBackup() {
        let rule = RuleStatus(
            index: 3, services: ["youtube"], via: ["nl", "de"], tunnel: "de", degraded: true, reason: .dead)
        let b = make(Status(tunnels: [tunnel("nl", state: .dead), tunnel("de")], rules: [rule])).banner
        XCTAssertEqual(b, Banner(kind: .ruleFallback, text: "youtube на резерве", target: .rule(3)))
    }

    func testBannerRuleInFallbackAndManyServices() {
        let rule = RuleStatus(
            index: 1, services: ["youtube", "ai"], via: ["nl"], inFallback: true, degraded: true, reason: .dead)
        let b = make(Status(tunnels: [tunnel("nl", state: .dead)], rules: [rule])).banner
        XCTAssertEqual(b?.kind, .ruleFallback)
        XCTAssertEqual(b?.text, "youtube и ещё 1 без туннеля")
        XCTAssertEqual(b?.target, .rule(1))
    }

    // design 7: intentional states (paused, disabled) are not a rule problem
    func testIntentionalRuleStatesGiveNoRuleBanner() {
        for reason in [RuleReason.disabled, .paused] {
            let rule = RuleStatus(
                index: 0, services: ["a"], via: ["nl"], inFallback: true, degraded: true, reason: reason)
            let b = make(Status(tunnels: [tunnel("nl", enabled: false, state: .off)], rules: [rule])).banner
            XCTAssertNotEqual(b?.kind, .ruleFallback, "\(reason)")
        }
    }

    // plan A3: config error > daemon unavailable > paused > rule on backup
    func testBannerPriority() {
        let rule = RuleStatus(
            index: 0, services: ["a"], via: ["nl"], inFallback: true, degraded: true, reason: .dead)
        let t = [tunnel("nl", state: .dead)]
        XCTAssertEqual(
            make(Status(paused: true, configErrorCount: 1, tunnels: t, rules: [rule])).banner?.kind, .configError)
        XCTAssertEqual(make(Status(paused: true, tunnels: t, rules: [rule])).banner?.kind, .paused)
        XCTAssertEqual(make(Status(tunnels: t, rules: [rule])).banner?.kind, .ruleFallback)
    }

    // MARK: action bar (design 5)

    func testActionBarTitles() {
        XCTAssertEqual(make(Status(canControl: true)).actions.pauseTitle, "Приостановить")
        XCTAssertEqual(make(Status(canControl: true, paused: true)).actions.pauseTitle, "Возобновить")
    }

    func testActionBarEnabledOnlyWhenCanControl() {
        let on = make(Status(canControl: true)).actions
        XCTAssertTrue(on.pauseEnabled && on.disableAllEnabled && on.reloadEnabled)
        let off = make(Status(canControl: false)).actions
        XCTAssertFalse(off.pauseEnabled || off.disableAllEnabled || off.reloadEnabled)
        let paused = make(Status(canControl: true, paused: true)).actions
        XCTAssertTrue(paused.pauseEnabled && paused.disableAllEnabled && paused.reloadEnabled)
    }

    func testActionBarDisabledWhenUnavailable() {
        for state in [EngineState.notInstalled, .notRunning, .outdated(apiVersion: 0)] {
            let m = WindowModel.make(from: state, now: now)
            XCTAssertFalse(
                m.actions.pauseEnabled || m.actions.disableAllEnabled || m.actions.reloadEnabled, "\(state)")
            XCTAssertEqual(m.actions.pauseTitle, "Приостановить")
            XCTAssertTrue(m.tunnels.isEmpty)
            XCTAssertTrue(m.rules.isEmpty)
        }
    }

    // MARK: tunnel details (design 5)

    func testTunnelDetailUp() {
        let peers = [
            PeerStatus(
                endpoint: "vpn.example.com:51820", lastHandshake: now.addingTimeInterval(-30),
                rxBytes: 1024, txBytes: 2048),
            PeerStatus(endpoint: "other.example.com:51820", lastHandshake: nil, rxBytes: 1024, txBytes: 0),
        ]
        let t = tunnel(
            "work", peers: peers, check: CheckStatus(addr: nil, rttMs: 12, fails: 0),
            interface: "utun5", addresses: ["10.0.0.2/32", "fd00::2/128"], routeCount: 7)
        let d = make(Status(canControl: true, tunnels: [t])).tunnels
        XCTAssertEqual(d.count, 1)
        XCTAssertEqual(d[0].row.name, "work")
        XCTAssertEqual(d[0].endpoint, "vpn.example.com:51820", "endpoint of the first peer")
        XCTAssertEqual(d[0].interface, "utun5")
        XCTAssertEqual(d[0].addresses, ["10.0.0.2/32", "fd00::2/128"])
        XCTAssertEqual(d[0].trafficText, "↓ 2,0 КБ ↑ 2,0 КБ", "summed over peers")
        XCTAssertEqual(d[0].routeCount, 7)
        XCTAssertEqual(d[0].checkText, "ok, 12 мс")
        XCTAssertNil(d[0].error)
        XCTAssertNil(d[0].reason)
    }

    func testHandshakeText() {
        let cases: [(Date?, String)] = [
            (now.addingTimeInterval(-30), "30 с назад"),
            (now.addingTimeInterval(-300), "5 мин назад"),
            (now.addingTimeInterval(-7200), "2 ч назад"),
            (nil, "нет"),
        ]
        for (when, want) in cases {
            let t = tunnel("a", peers: [PeerStatus(lastHandshake: when)])
            XCTAssertEqual(make(Status(tunnels: [t])).tunnels[0].handshakeText, want)
        }
    }

    // TunnelDetail docs: handshake and traffic are nil without peers
    func testNoPeers() {
        let d = make(Status(tunnels: [tunnel("a", enabled: false, state: .off)])).tunnels[0]
        XCTAssertNil(d.handshakeText)
        XCTAssertNil(d.trafficText)
        XCTAssertNil(d.endpoint)
        XCTAssertNil(d.interface)
        XCTAssertNil(d.checkText)
        XCTAssertEqual(d.routeCount, 0)
        XCTAssertTrue(d.addresses.isEmpty)
    }

    // redacted reply: peers without endpoint
    func testEndpointRedacted() {
        let t = tunnel("a", peers: [PeerStatus(endpoint: nil)])
        XCTAssertNil(make(Status(tunnels: [t])).tunnels[0].endpoint)
    }

    func testCheckText() {
        let cases: [(CheckStatus?, String?)] = [
            (CheckStatus(rttMs: 12, fails: 0), "ok, 12 мс"),
            (CheckStatus(rttMs: nil, fails: 3), "сбоев: 3"),
            (CheckStatus(lastOK: nil, rttMs: nil, fails: 1), "сбоев: 1"),
            (nil, nil),
        ]
        for (check, want) in cases {
            let t = tunnel("a", peers: [PeerStatus()], check: check)
            XCTAssertEqual(make(Status(tunnels: [t])).tunnels[0].checkText, want, "\(String(describing: check))")
        }
    }

    func testTunnelErrorAndReason() {
        let err = tunnel("home", state: .error, error: "resolve: no such host")
        let dead = tunnel("nl", state: .dead, interface: "utun4", reason: "no handshake")
        let d = make(Status(tunnels: [err, dead])).tunnels
        XCTAssertEqual(d[0].error, "resolve: no such host")
        XCTAssertNil(d[0].reason)
        XCTAssertEqual(d[1].reason, "no handshake")
        XCTAssertNil(d[1].error)
    }

    // the row has the flags of the menu row; startsOnResume is passed through
    func testRowMatchesMenuAndStartsOnResume() {
        let st = Status(
            canControl: true, paused: true,
            tunnels: [tunnel("nl"), tunnel("de", enabled: false, state: .off)])
        let m = make(st, resume: ["nl", "de"])
        let menu = MenuModel.make(from: .ready(st), startsOnResume: ["nl", "de"])
        XCTAssertEqual(m.tunnels.map(\.row), menu.tunnels)
        XCTAssertEqual(m.tunnels.map(\.row.name), ["nl", "de"])
        XCTAssertTrue(m.tunnels[0].row.startsOnResume)
        let live = make(Status(tunnels: [tunnel("nl")]), resume: ["nl"])
        XCTAssertFalse(live.tunnels[0].row.startsOnResume, "only while paused, as in the menu")
    }

    func testRowEnabledFollowsCanControl() {
        XCTAssertFalse(make(Status(canControl: false, tunnels: [tunnel("a")])).tunnels[0].row.enabled)
        XCTAssertTrue(make(Status(canControl: true, tunnels: [tunnel("a")])).tunnels[0].row.enabled)
    }

    // MARK: rules (design 5)

    func testRuleRows() {
        let rules = [
            RuleStatus(index: 0, services: ["youtube", "ai"], via: ["nl", "de"], tunnel: "nl"),
            RuleStatus(index: 1, services: ["x"], via: ["nl", "de"], tunnel: "de", degraded: true, reason: .dead),
            RuleStatus(index: 2, services: ["y"], via: ["nl"], inFallback: true, degraded: true, reason: .dead),
            RuleStatus(index: 3, services: ["z"], via: [], tunnel: nil),
        ]
        let rows = make(Status(rules: rules)).rules
        XCTAssertEqual(rows.map(\.index), [0, 1, 2, 3])
        XCTAssertEqual(rows[0].services, ["youtube", "ai"])
        XCTAssertEqual(rows[0].via, ["nl", "de"])
        XCTAssertEqual(rows.map(\.tunnel), ["nl", "de", nil, nil])
        XCTAssertEqual(rows.map(\.stateText), ["ok", "на резерве", "без туннеля", "напрямую"])
        XCTAssertEqual(rows.map(\.isProblem), [false, true, true, false])
        XCTAssertNil(rows[0].reasonText)
        XCTAssertNotNil(rows[1].reasonText)
        XCTAssertNotNil(rows[2].reasonText)
        XCTAssertNil(rows[3].reasonText)
    }

    // design 7: only reason dead (or unknown) is a problem; paused and disabled are intentional
    func testRuleProblemCriterion() {
        let cases: [(RuleReason?, Bool)] = [(.dead, true), (nil, true), (.disabled, false), (.paused, false)]
        for (reason, want) in cases {
            let r = RuleStatus(
                index: 0, services: ["a"], via: ["nl"], inFallback: true, degraded: true, reason: reason)
            XCTAssertEqual(make(Status(rules: [r])).rules[0].isProblem, want, "\(String(describing: reason))")
        }
    }

    // MARK: ConfigDirAccess (design 5)

    func testConfigDirAccess() {
        let path = "/opt/homebrew/etc/wgplex"
        XCTAssertEqual(ConfigDirAccess.describe(path: path, canRead: true), .open(path))
        XCTAssertEqual(ConfigDirAccess.describe(path: path, canRead: false), .adminOnly(path))
        XCTAssertNil(ConfigDirAccess.describe(path: path, canRead: true).note)
        XCTAssertEqual(ConfigDirAccess.describe(path: path, canRead: false).note, "Конфиг правит администратор")
    }
}
