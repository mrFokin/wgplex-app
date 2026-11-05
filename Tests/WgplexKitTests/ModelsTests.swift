import XCTest

@testable import WgplexKit

/// Decoding of the reply types (docs/api.md "Data structures", "Redaction").
final class ModelsTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    private func date(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)!
    }

    // MARK: Status

    func testFullStatus() throws {
        let s = try decode(Status.self, Fixture.statusFull)
        XCTAssertEqual(s.apiVersion, 1)
        XCTAssertEqual(s.version, "0.1.0-dev")
        XCTAssertTrue(s.canControl)
        XCTAssertEqual(s.controlGroup, "admin")
        XCTAssertTrue(s.configured)
        XCTAssertFalse(s.blockSnapshot)
        XCTAssertFalse(s.paused)
        XCTAssertEqual(s.configDir, "/opt/homebrew/etc/wgplex")
        XCTAssertEqual(s.logPath, "/opt/homebrew/var/log/wgplex.log")
        XCTAssertEqual(s.icon, .warn)
        XCTAssertEqual(s.configErrors, ["wg0.conf: bad line"])
        XCTAssertEqual(s.configErrorCount, 1)
        XCTAssertEqual(s.warnings, ["rule 1: unused service"])
        XCTAssertEqual(s.warningCount, 1)
        XCTAssertEqual(s.tunnels.map(\.name), ["work", "home"])
        XCTAssertEqual(s.rules.map(\.index), [0, 1])

        let work = s.tunnels[0]
        XCTAssertEqual(work.id, "work")
        XCTAssertTrue(work.enabled)
        XCTAssertEqual(work.state, .up)
        XCTAssertNil(work.error)
        XCTAssertEqual(work.interface, "utun5")
        XCTAssertEqual(work.addresses, ["10.0.0.2/32", "fd00::2/128"])
        XCTAssertEqual(work.routes, .rules)
        XCTAssertEqual(work.routeCount, 7)
        XCTAssertNil(work.reason)
        XCTAssertEqual(work.peers.count, 1)
        let peer = work.peers[0]
        XCTAssertEqual(peer.endpoint, "vpn.example.com:51820")
        XCTAssertEqual(peer.resolved, "203.0.113.7:51820")
        XCTAssertEqual(peer.rxBytes, 1024)
        XCTAssertEqual(peer.txBytes, 2048)
        XCTAssertEqual(work.check?.addr, "https://check.example.com/?token=abc")
        XCTAssertEqual(work.check?.rttMs, 12.5)
        XCTAssertEqual(work.check?.fails, 0)

        let home = s.tunnels[1]
        XCTAssertEqual(home.state, .error)
        XCTAssertEqual(home.error, "resolve vpn.home.example: no such host")
        XCTAssertEqual(home.routes, .config)
        XCTAssertNil(home.interface)
        XCTAssertEqual(home.addresses, [])  // omitted when empty
        XCTAssertEqual(home.peers, [])  // omitted otherwise
        XCTAssertNil(home.check)

        let r0 = s.rules[0]
        XCTAssertEqual(r0.services, ["telegram", "youtube"])
        XCTAssertEqual(r0.via, ["work", "home"])
        XCTAssertEqual(r0.fallback, .block)
        XCTAssertEqual(r0.tunnel, "work")
        XCTAssertFalse(r0.inFallback)
        XCTAssertFalse(r0.degraded)
        XCTAssertNil(r0.reason)
        XCTAssertEqual(s.rules[1].reason, .dead)
        XCTAssertEqual(s.rules[1].fallback, .default)
    }

    // api: Redaction. Without can_control the redacted fields are absent.
    func testRedactedStatusWithoutCanControl() throws {
        let s = try decode(Status.self, Fixture.statusRedacted)
        XCTAssertFalse(s.canControl)
        XCTAssertEqual(s.configErrors, [])
        XCTAssertEqual(s.configErrorCount, 2)
        XCTAssertEqual(s.warnings, [])
        XCTAssertEqual(s.warningCount, 3)
        let work = s.tunnels[0]
        XCTAssertEqual(work.state, .dead)
        XCTAssertNil(work.reason)
        XCTAssertNil(work.check?.addr)
        XCTAssertEqual(work.check?.fails, 4)
        XCTAssertNil(work.peers[0].endpoint)
        XCTAssertNil(work.peers[0].resolved)
        XCTAssertEqual(work.peers[0].rxBytes, 5)
        XCTAssertEqual(work.peers[0].txBytes, 6)
        XCTAssertEqual(s.tunnels[1].state, .error)
        XCTAssertNil(s.tunnels[1].error)
        XCTAssertEqual(s.rules, [])
    }

    func testPausedStatus() throws {
        let s = try decode(Status.self, Fixture.statusPaused)
        XCTAssertTrue(s.paused)
        XCTAssertEqual(s.icon, .paused)
        XCTAssertEqual(s.tunnels[0].state, .off)
        XCTAssertTrue(s.tunnels[0].enabled, "the toggle is kept on pause")
        XCTAssertEqual(s.rules[0].reason, .paused)
        XCTAssertTrue(s.rules[0].inFallback)
        XCTAssertTrue(s.rules[0].degraded)
    }

    func testNotConfiguredWithBlockSnapshot() throws {
        let s = try decode(Status.self, Fixture.statusNotConfigured)
        XCTAssertFalse(s.configured)
        XCTAssertTrue(s.blockSnapshot)
        XCTAssertEqual(s.icon, .warn)
        XCTAssertEqual(s.configErrors, ["no such directory"])
        XCTAssertEqual(s.tunnels, [])
        XCTAssertEqual(s.rules, [])
    }

    func testRuleReasons() throws {
        let s = try decode(Status.self, Fixture.statusDegraded)
        XCTAssertEqual(s.rules.map(\.reason), [.dead, .disabled, .paused, nil])
        XCTAssertEqual(s.rules.map(\.degraded), [true, true, true, false])
        XCTAssertEqual(s.rules[0].tunnel, "t2", "served by a backup")
        XCTAssertNil(s.rules[1].tunnel)
        XCTAssertEqual(s.rules[3].via, [])
    }

    // api: Versioning. Unknown fields are ignored.
    func testUnknownFieldsAreIgnored() throws {
        let json = """
            {"api_version": 1, "version": "9", "future": {"a": [1, 2]}, "icon": "on",
             "tunnels": [{"name": "t", "enabled": false, "state": "off", "routes": "config",
                          "route_count": 0, "new_field": 5,
                          "peers": [{"rx_bytes": 1, "tx_bytes": 2, "extra": true}],
                          "check": {"fails": 0, "extra": "x"}}],
             "rules": [{"index": 0, "services": [], "via": [], "fallback": "default",
                        "in_fallback": false, "degraded": false, "extra": null}]}
            """
        let s = try decode(Status.self, json)
        XCTAssertEqual(s.icon, .on)
        XCTAssertEqual(s.tunnels.count, 1)
        XCTAssertEqual(s.rules.count, 1)
    }

    // api: Versioning. A new value of an enum does not break decoding.
    func testUnknownEnumValues() throws {
        let json = """
            {"api_version": 2, "version": "9", "icon": "rainbow",
             "tunnels": [{"name": "t", "enabled": true, "state": "hibernating", "routes": "magic",
                          "route_count": 0}],
             "rules": [{"index": 0, "services": [], "via": ["t"], "fallback": "tarpit",
                        "in_fallback": true, "degraded": true, "reason": "cosmic"}]}
            """
        let s = try decode(Status.self, json)
        XCTAssertEqual(s.icon, .unknown("rainbow"))
        XCTAssertEqual(s.tunnels[0].state, .unknown("hibernating"))
        XCTAssertEqual(s.tunnels[0].routes, .unknown("magic"))
        XCTAssertEqual(s.rules[0].fallback, .unknown("tarpit"))
        XCTAssertEqual(s.rules[0].reason, .unknown("cosmic"))
    }

    // api: Icon / TunnelStatus.state tables: every known value.
    func testKnownEnumValues() throws {
        for (raw, want) in [("off", Icon.off), ("on", .on), ("warn", .warn), ("paused", .paused)] {
            XCTAssertEqual(try decode(Icon.self, "\"\(raw)\""), want, raw)
        }
        for (raw, want) in [
            ("off", TunnelState.off), ("starting", .starting), ("up", .up), ("dead", .dead), ("error", .error),
        ] {
            XCTAssertEqual(try decode(TunnelState.self, "\"\(raw)\""), want, raw)
        }
        XCTAssertEqual(try decode(RouteMode.self, "\"config\""), .config)
        XCTAssertEqual(try decode(RouteMode.self, "\"rules\""), .rules)
        XCTAssertEqual(try decode(Fallback.self, "\"default\""), .default)
        XCTAssertEqual(try decode(Fallback.self, "\"block\""), .block)
        XCTAssertEqual(try decode(RuleReason.self, "\"dead\""), .dead)
        XCTAssertEqual(try decode(RuleReason.self, "\"disabled\""), .disabled)
        XCTAssertEqual(try decode(RuleReason.self, "\"paused\""), .paused)
        XCTAssertEqual(try decode(ExplanationKind.self, "\"domain\""), .domain)
        XCTAssertEqual(try decode(ExplanationKind.self, "\"ip\""), .ip)
        XCTAssertEqual(try decode(RouteTarget.self, "\"tunnel\""), .tunnel)
        XCTAssertEqual(try decode(RouteTarget.self, "\"direct\""), .direct)
        XCTAssertEqual(try decode(RouteTarget.self, "\"reject\""), .reject)
        XCTAssertEqual(try decode(RouteSource.self, "\"endpoint\""), .endpoint)
        XCTAssertEqual(try decode(RouteSource.self, "\"allowed-ips\""), .allowedIPs)
        XCTAssertEqual(try decode(RouteSource.self, "\"rule-cidr\""), .ruleCIDR)
        XCTAssertEqual(try decode(RouteSource.self, "\"dynamic\""), .dynamic)
    }

    func testUnknownValuesOfOtherEnums() throws {
        XCTAssertEqual(try decode(ExplanationKind.self, "\"mac\""), .unknown("mac"))
        XCTAssertEqual(try decode(RouteTarget.self, "\"blackhole\""), .unknown("blackhole"))
        XCTAssertEqual(try decode(RouteSource.self, "\"bgp\""), .unknown("bgp"))
    }

    // A reply without api_version reads as an old engine (0), not as current.
    func testMissingAPIVersionIsZero() throws {
        XCTAssertEqual(try decode(Status.self, "{}").apiVersion, 0)
    }

    // api: minimal reply, every omitted field has a default.
    func testOmittedFieldsGetDefaults() throws {
        let s = try decode(Status.self, #"{"api_version": 1}"#)
        XCTAssertEqual(s.apiVersion, 1)
        XCTAssertFalse(s.canControl)
        XCTAssertFalse(s.configured)
        XCTAssertFalse(s.blockSnapshot)
        XCTAssertFalse(s.paused)
        XCTAssertEqual(s.configErrors, [])
        XCTAssertEqual(s.configErrorCount, 0)
        XCTAssertEqual(s.warnings, [])
        XCTAssertEqual(s.warningCount, 0)
        XCTAssertEqual(s.tunnels, [])
        XCTAssertEqual(s.rules, [])

        let t = try decode(TunnelStatus.self, #"{"name": "t", "enabled": false, "state": "off", "routes": "config"}"#)
        XCTAssertNil(t.error)
        XCTAssertNil(t.interface)
        XCTAssertNil(t.reason)
        XCTAssertNil(t.check)
        XCTAssertEqual(t.addresses, [])
        XCTAssertEqual(t.peers, [])
        XCTAssertEqual(t.routeCount, 0)
    }

    // MARK: Times

    // api: Conventions, times are RFC 3339 strings.
    func testTimesWithAndWithoutFraction() throws {
        let p1 = try decode(PeerStatus.self, #"{"last_handshake": "2026-11-05T10:20:30.123456789Z"}"#)
        let want = date("2026-11-05T10:20:30Z")
        XCTAssertEqual(p1.lastHandshake!.timeIntervalSince(want), 0.123, accuracy: 0.001)

        let p2 = try decode(PeerStatus.self, #"{"last_handshake": "2026-11-05T10:20:30Z"}"#)
        XCTAssertEqual(p2.lastHandshake, want)

        let p3 = try decode(PeerStatus.self, #"{"last_handshake": "2026-11-05T13:20:30+03:00"}"#)
        XCTAssertEqual(p3.lastHandshake, want)

        let p4 = try decode(PeerStatus.self, #"{"last_handshake": "2026-11-05T10:20:30.5+00:00"}"#)
        XCTAssertEqual(p4.lastHandshake!.timeIntervalSince(want), 0.5, accuracy: 0.001)
    }

    func testFullStatusTimes() throws {
        let s = try decode(Status.self, Fixture.statusFull)
        let t = s.tunnels[0]
        XCTAssertEqual(
            t.peers[0].lastHandshake!.timeIntervalSince(date("2026-11-05T10:20:30Z")), 0.123, accuracy: 0.001)
        XCTAssertEqual(t.check?.lastOK, date("2026-11-05T10:20:31Z"))
    }

    // api: "omitted when zero (never)" -> nil.
    func testOmittedTimesAreNil() throws {
        let p = try decode(PeerStatus.self, #"{"rx_bytes": 1, "tx_bytes": 2}"#)
        XCTAssertNil(p.lastHandshake)
        let c = try decode(CheckStatus.self, #"{"fails": 3}"#)
        XCTAssertNil(c.lastOK)
        XCTAssertNil(c.rttMs)
        XCTAssertEqual(c.fails, 3)
    }

    // MARK: Explanation, Routes, results

    func testExplanationDomain() throws {
        let e = try decode(Explanation.self, Fixture.explainDomain)
        XCTAssertEqual(e.query, "example.com")
        XCTAssertEqual(e.kind, .domain)
        XCTAssertEqual(e.rule?.tunnel, "work")
        XCTAssertEqual(e.skipped?.index, 2)
        XCTAssertEqual(e.skipped?.reason, .dead)
        XCTAssertEqual(e.upstream, "work")
        XCTAssertEqual(e.zone, "example.com")
        XCTAssertEqual(e.servers, ["10.0.0.1"])
        XCTAssertTrue(e.dropAAAA)
        XCTAssertEqual(e.addrs, ["93.184.216.34"])
        XCTAssertNil(e.route)
    }

    func testExplanationIPAndBare() throws {
        let e = try decode(Explanation.self, Fixture.explainIP)
        XCTAssertEqual(e.kind, .ip)
        XCTAssertEqual(e.route?.prefix, "93.184.216.0/24")
        XCTAssertEqual(e.route?.target, .tunnel)
        XCTAssertEqual(e.route?.source, .ruleCIDR)
        XCTAssertEqual(e.route?.rule, 0)
        XCTAssertEqual(e.rule?.index, 0)

        let b = try decode(Explanation.self, Fixture.explainBare)
        XCTAssertNil(b.rule)
        XCTAssertNil(b.skipped)
        XCTAssertNil(b.upstream)
        XCTAssertNil(b.zone)
        XCTAssertNil(b.route)
        XCTAssertEqual(b.servers, [])
        XCTAssertEqual(b.addrs, [])
        XCTAssertFalse(b.dropAAAA)
    }

    func testRoutes() throws {
        let r = try decode(Routes.self, Fixture.routes)
        XCTAssertEqual(r.syncError, "route add: file exists")
        XCTAssertEqual(r.routes.map(\.target), [.tunnel, .direct, .reject, .tunnel])
        XCTAssertEqual(r.routes.map(\.source), [.allowedIPs, .endpoint, .ruleCIDR, .dynamic])
        XCTAssertEqual(r.routes.map(\.rule), [-1, -1, 1, 0])
        XCTAssertEqual(r.routes[2].tunnel, "home", "a reject route keeps its tunnel")
        XCTAssertNil(r.routes[1].tunnel)
        XCTAssertEqual(r.routes[3].names, ["a.example.com"])
        XCTAssertEqual(r.routes[3].skipped, "no physical gateway")
        XCTAssertNil(r.routes[0].skipped)
        XCTAssertEqual(r.routes[0].names, [])

        let empty = try decode(Routes.self, #"{"routes": []}"#)
        XCTAssertNil(empty.syncError)
    }

    func testApplyResult() throws {
        let a = try decode(ApplyResult.self, Fixture.applyResult)
        XCTAssertEqual(a.warnings, ["w1"])
        XCTAssertEqual(a.tunnels, [TunnelError(name: "home", error: "boom")])
        let m = try decode(ApplyResult.self, Fixture.applyResultMinimal)
        XCTAssertEqual(m.tunnels, [])
        XCTAssertEqual(m.warnings, [])
    }

    func testEnableResult() throws {
        XCTAssertFalse(try decode(EnableResult.self, "{}").startsOnResume)
        XCTAssertTrue(try decode(EnableResult.self, #"{"starts_on_resume": true}"#).startsOnResume)
    }
}
