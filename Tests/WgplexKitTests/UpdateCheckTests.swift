import XCTest

@testable import WgplexKit

final class UpdateCheckTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func release(tag: String = "v1.3.0", url: String = "https://github.com/mrFokin/wgplex-app/releases/tag/v1.3.0")
        -> Data
    {
        Data(#"{"tag_name": "\#(tag)", "html_url": "\#(url)"}"#.utf8)
    }

    private struct NetError: Error {}

    // MARK: parse (design 2)

    func testParseRelease() {
        let u = UpdateCheck.parse(release())
        XCTAssertEqual(u?.version, "1.3.0")
        XCTAssertEqual(u?.url, "https://github.com/mrFokin/wgplex-app/releases/tag/v1.3.0")
        XCTAssertEqual(u?.command, "brew upgrade --cask wgplex-app")
    }

    func testParseTagWithoutV() {
        XCTAssertEqual(UpdateCheck.parse(release(tag: "1.3.0"))?.version, "1.3.0")
    }

    func testParseIgnoresUnknownFields() {
        let json = #"""
            {"id": 1, "name": "x", "draft": false, "assets": [{"name": "a.dmg"}],
             "tag_name": "v2.0.1", "html_url": "https://example.test/r", "body": "notes"}
            """#
        XCTAssertEqual(UpdateCheck.parse(Data(json.utf8)), UpdateInfo(version: "2.0.1", url: "https://example.test/r"))
    }

    func testParseGarbage() {
        let cases: [(String, String)] = [
            ("not json", "garbage"),
            ("", "empty body"),
            ("[]", "array"),
            ("{}", "empty object"),
            (#"{"message": "Not Found"}"#, "404 body"),
            (#"{"tag_name": "v1.3.0"}"#, "no html_url"),
            (#"{"html_url": "https://e.test/r"}"#, "no tag_name"),
            (#"{"tag_name": "", "html_url": "https://e.test/r"}"#, "empty tag"),
            (#"{"tag_name": "v", "html_url": "https://e.test/r"}"#, "only v"),
            (#"{"tag_name": "v1.3.0", "html_url": ""}"#, "empty url"),
            (#"{"tag_name": null, "html_url": "https://e.test/r"}"#, "null tag"),
            (#"{"tag_name": "v1.3.0", "html_url": null}"#, "null url"),
            (#"{"tag_name": 5, "html_url": "https://e.test/r"}"#, "numeric tag"),
            (#"{"tag_name": "latest", "html_url": "https://e.test/r"}"#, "non-numeric version"),
            (#"{"tag_name": "nightly-1", "html_url": "https://e.test/r"}"#, "non-numeric version 2"),
        ]
        for (json, why) in cases {
            XCTAssertNil(UpdateCheck.parse(Data(json.utf8)), why)
        }
    }

    // MARK: isNewer

    func testIsNewer() {
        let cases: [(String, String, Bool)] = [
            ("1.3.0", "1.2.9", true),
            ("1.10.0", "1.9.0", true),  // numeric, not lexicographic
            ("2.0.0", "1.99.99", true),
            ("1.2.1", "1.2", true),
            ("1.3", "1.3.0", false),  // missing components count as 0
            ("1.3.0", "1.3", false),
            ("1.3.0", "1.3.0", false),
            ("1.2.9", "1.3.0", false),
            ("0.1.0", "0.1.0-dev", true),  // pre-release sorts below release
            ("0.1.0-dev", "0.1.0", false),
            ("0.1.0-dev", "0.1.0-dev", false),
            ("0.2.0", "0.1.0-dev", true),
            ("garbage", "1.0.0", false),  // unparsable is never newer
            ("1.0.0", "garbage", false),
            ("", "1.0.0", false),
        ]
        for (c, cur, want) in cases {
            XCTAssertEqual(UpdateCheck.isNewer(c, than: cur), want, "\(c) vs \(cur)")
        }
    }

    func testIsNewerDefaultsToAppVersion() {
        XCTAssertTrue(UpdateCheck.isNewer("999.0.0"))
        XCTAssertFalse(UpdateCheck.isNewer("0.0.1"))
    }

    // MARK: isDue (design 2: once a day)

    func testIntervalIsADay() {
        XCTAssertEqual(UpdateCheck.interval, 86_400)
    }

    func testIsDue() {
        let cases: [(Date?, Bool, String)] = [
            (nil, true, "never checked"),
            (now.addingTimeInterval(-60), false, "a minute ago"),
            (now.addingTimeInterval(-86_399), false, "just under a day"),
            (now.addingTimeInterval(-86_400), true, "exactly a day"),
            (now.addingTimeInterval(-3 * 86_400), true, "days ago"),
            (now.addingTimeInterval(3600), true, "clock moved back"),
        ]
        for (last, want, why) in cases {
            XCTAssertEqual(UpdateCheck(lastCheck: last).isDue(now: now), want, why)
        }
    }

    // MARK: check

    func testCheckFindsNewerVersion() async {
        var c = UpdateCheck()
        let u = await c.check(now: now, current: "1.2.0") { self.release() }
        guard case .available(let info) = u else { return XCTFail("\(u)") }
        XCTAssertEqual(info.version, "1.3.0")
        XCTAssertEqual(c.lastCheck, now)
    }

    func testCheckUpToDate() async {
        var c = UpdateCheck()
        let same = await c.check(now: now, current: "1.3.0") { self.release() }
        XCTAssertEqual(same, .upToDate)
        XCTAssertEqual(c.lastCheck, now)
        var c2 = UpdateCheck()
        let older = await c2.check(now: now, current: "2.0.0") { self.release() }
        XCTAssertEqual(older, .upToDate)
    }

    func testCheckNotDueDoesNotFetch() async {
        var c = UpdateCheck(lastCheck: now.addingTimeInterval(-3600))
        var called = false
        let u = await c.check(now: now, current: "1.0.0") {
            called = true
            return self.release()
        }
        XCTAssertEqual(u, .notDue)
        XCTAssertFalse(called)
        XCTAssertEqual(c.lastCheck, now.addingTimeInterval(-3600))
    }

    func testCheckDueAfterADay() async {
        var c = UpdateCheck(lastCheck: now.addingTimeInterval(-86_400))
        let u = await c.check(now: now, current: "1.0.0") { self.release() }
        guard case .available = u else { return XCTFail("\(u)") }
        XCTAssertEqual(c.lastCheck, now)
    }

    // failures are silent and recorded, so a broken network is retried only after a day
    func testCheckFailuresAreSilentAndRecorded() async {
        let fetchers: [(String, () async throws -> Data)] = [
            ("network error", { throw NetError() }),
            ("404 body", { Data(#"{"message": "Not Found"}"#.utf8) }),
            ("bad json", { Data("<html>".utf8) }),
            ("empty fields", { Data(#"{"tag_name": "", "html_url": ""}"#.utf8) }),
        ]
        for (why, fetch) in fetchers {
            var c = UpdateCheck()
            let u = await c.check(now: now, current: "1.0.0", fetch: fetch)
            XCTAssertEqual(u, .failed, why)
            XCTAssertEqual(c.lastCheck, now, why)
            XCTAssertFalse(c.isDue(now: now.addingTimeInterval(3600)), why)
        }
    }

    func testCheckDoesNotTouchNotifiedVersion() async {
        var c = UpdateCheck(notifiedVersion: "1.3.0")
        _ = await c.check(now: now, current: "1.0.0") { self.release() }
        XCTAssertEqual(c.notifiedVersion, "1.3.0")
    }

    // MARK: shouldNotify (design 7: once per version)

    func testShouldNotifyOncePerVersion() {
        var c = UpdateCheck()
        let v13 = UpdateInfo(version: "1.3.0", url: "u")
        XCTAssertTrue(c.shouldNotify(v13))
        XCTAssertEqual(c.notifiedVersion, "1.3.0")
        XCTAssertFalse(c.shouldNotify(v13))
        XCTAssertFalse(c.shouldNotify(v13))
        let v14 = UpdateInfo(version: "1.4.0", url: "u2")
        XCTAssertTrue(c.shouldNotify(v14))
        XCTAssertEqual(c.notifiedVersion, "1.4.0")
        XCTAssertFalse(c.shouldNotify(v14))
    }

    func testShouldNotifyAlreadyNotifiedAtInit() {
        var c = UpdateCheck(notifiedVersion: "1.3.0")
        XCTAssertFalse(c.shouldNotify(UpdateInfo(version: "1.3.0", url: "u")))
    }
}
