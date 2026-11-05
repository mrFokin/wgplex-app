import XCTest

@testable import WgplexKit

final class LogTailTests: XCTestCase {
    private func data(_ s: String) -> Data { Data(s.utf8) }

    private func tail(maxBytes: Int = 256 * 1024, maxLines: Int = 2000, _ chunks: String...) -> LogTail {
        var t = LogTail(maxBytes: maxBytes, maxLines: maxLines)
        for c in chunks { t.append(data(c)) }
        return t
    }

    // design 5: level= from the slog TextHandler; anything else is unknown
    func testLevelParsing() {
        let cases: [(String, LogLevel)] = [
            (#"time=2026-11-05T10:00:00Z level=DEBUG msg="x""#, .debug),
            (#"time=2026-11-05T10:00:00Z level=INFO msg="x""#, .info),
            (#"time=2026-11-05T10:00:00Z level=WARN msg="x""#, .warn),
            (#"time=2026-11-05T10:00:00Z level=ERROR msg="x""#, .error),
            (#"time=2026-11-05T10:00:00Z level=TRACE msg="x""#, .unknown),
            (#"time=2026-11-05T10:00:00Z msg="no level""#, .unknown),
            ("plain text line", .unknown),
        ]
        for (text, want) in cases {
            let t = tail(text + "\n")
            XCTAssertEqual(t.lines, [LogLine(text: text, level: want)], text)
        }
    }

    func testLevelOrder() {
        XCTAssertLessThan(LogLevel.unknown, .debug)
        XCTAssertLessThan(LogLevel.debug, .info)
        XCTAssertLessThan(LogLevel.info, .warn)
        XCTAssertLessThan(LogLevel.warn, .error)
    }

    // design 5: lines come without the trailing newline, oldest first
    func testMultipleLinesInOneChunk() {
        let t = tail("level=INFO a\nlevel=WARN b\nlevel=ERROR c\n")
        XCTAssertEqual(t.lines.map(\.text), ["level=INFO a", "level=WARN b", "level=ERROR c"])
    }

    // design 5: tailing; offset advances by the number of bytes appended
    func testOffsetAdvances() {
        var t = LogTail()
        XCTAssertEqual(t.offset, 0)
        t.append(data("level=INFO a\n"))
        XCTAssertEqual(t.offset, 13)
        t.append(data("level=INFO b\n"))
        XCTAssertEqual(t.offset, 26)
    }

    // design 5: a trailing partial line is held back until its newline arrives
    func testPartialLineIsHeldBack() {
        var t = LogTail()
        t.append(data("level=INFO one\nlevel=WA"))
        XCTAssertEqual(t.lines.map(\.text), ["level=INFO one"])
        XCTAssertEqual(t.offset, 23, "offset counts the held-back bytes too")
        t.append(data("RN two\n"))
        XCTAssertEqual(t.lines.map(\.text), ["level=INFO one", "level=WARN two"])
        XCTAssertEqual(t.lines.last?.level, .warn)
    }

    func testPartialLineAcrossThreeChunks() {
        let t = tail("lev", "el=ERR", "OR boom\n")
        XCTAssertEqual(t.lines, [LogLine(text: "level=ERROR boom", level: .error)])
    }

    func testChunkWithoutNewlineAddsNothing() {
        let t = tail("level=INFO no newline yet")
        XCTAssertTrue(t.lines.isEmpty)
    }

    // a multi-byte character split between two reads
    func testUTF8SplitAcrossChunks() {
        let bytes = Array("level=INFO héllo\n".utf8)
        let cut = bytes.firstIndex(of: 0xC3)! + 1  // between the two bytes of "é"
        var t = LogTail()
        t.append(Data(bytes[..<cut]))
        t.append(Data(bytes[cut...]))
        XCTAssertEqual(t.lines.map(\.text), ["level=INFO héllo"])
    }

    // append doc: invalid UTF-8 is replaced, not dropped, no crash
    func testInvalidUTF8IsReplaced() {
        var t = LogTail()
        t.append(Data([0x6F, 0x6B, 0xFF, 0x0A]) + data("next\n"))
        XCTAssertEqual(t.lines.count, 2)
        XCTAssertTrue(t.lines[0].text.hasPrefix("ok"))
        XCTAssertEqual(t.lines[1].text, "next")
    }

    // append doc: first read of a large file starts mid-line, the partial first line is dropped
    func testMidLineStartIsDropped() {
        var t = LogTail()
        t.offset = 1000
        let chunk = "tial of a cut line\nlevel=INFO whole\n"
        t.append(data(chunk))
        XCTAssertEqual(t.lines.map(\.text), ["level=INFO whole"])
        XCTAssertEqual(t.offset, 1000 + UInt64(chunk.utf8.count))
    }

    // reading from offset 0 starts at a line boundary: nothing is dropped
    func testFirstLineKeptAtOffsetZero() {
        let t = tail("level=INFO first\n")
        XCTAssertEqual(t.lines.map(\.text), ["level=INFO first"])
    }

    // design 5 / plan 5: buffer limit by lines, the newest stay
    func testMaxLinesKeepsNewest() {
        var t = LogTail(maxBytes: 1 << 20, maxLines: 3)
        t.append(data((1...5).map { "line \($0)\n" }.joined()))
        XCTAssertEqual(t.lines.map(\.text), ["line 3", "line 4", "line 5"])
        t.append(data("line 6\n"))
        XCTAssertEqual(t.lines.map(\.text), ["line 4", "line 5", "line 6"])
    }

    // append doc / plan 1: cut by maxBytes on a line boundary, the newest stay
    func testMaxBytesCutsOnLineBoundary() {
        var t = LogTail(maxBytes: 20, maxLines: 2000)
        let all = ["l1aaaaaa", "l2aaaaaa", "l3aaaaaa", "l4aaaaaa"]  // 9 bytes each with newline
        t.append(data(all.map { $0 + "\n" }.joined()))
        XCTAssertFalse(t.lines.isEmpty)
        XCTAssertEqual(t.lines.last?.text, "l4aaaaaa", "the newest line stays")
        for l in t.lines { XCTAssertTrue(all.contains(l.text), "whole lines only: \(l.text)") }
        let total = t.lines.reduce(0) { $0 + $1.text.utf8.count + 1 }
        XCTAssertLessThanOrEqual(total, 20)
        let kept = t.lines.map(\.text)
        XCTAssertEqual(kept, Array(all.suffix(kept.count)), "contiguous tail, no gaps")
    }

    // reset doc: file truncated or rotated
    func testResetClearsEverything() {
        var t = LogTail()
        t.append(data("level=INFO a\npartial"))
        XCTAssertGreaterThan(t.offset, 0)
        t.reset()
        XCTAssertEqual(t.offset, 0)
        XCTAssertTrue(t.lines.isEmpty)
        t.append(data("level=INFO b\n"))
        XCTAssertEqual(t.lines.map(\.text), ["level=INFO b"], "held-back partial line is gone")
        XCTAssertEqual(t.offset, 13)
    }

    // MARK: filtered

    private var mixed: LogTail {
        tail(
            "level=DEBUG msg=\"Dns lookup\"\n", "level=INFO msg=\"tunnel up\" name=nl\n",
            "level=WARN msg=\"slow check\" name=de\n", "level=ERROR msg=\"Tunnel down\" name=nl\n",
            "stack trace without level\n")
    }

    // design 5: filter by minimum level
    func testFilterByLevel() {
        let cases: [(LogLevel?, Int)] = [(nil, 5), (.debug, 4), (.info, 3), (.warn, 2), (.error, 1)]
        for (level, count) in cases {
            XCTAssertEqual(mixed.filtered(level: level, query: "").count, count, "\(String(describing: level))")
        }
        XCTAssertEqual(mixed.filtered(level: .warn, query: "").map(\.level), [.warn, .error])
    }

    // filtered doc: unknown passes only without a level filter
    func testUnknownOnlyWithoutLevel() {
        XCTAssertTrue(mixed.filtered(level: nil, query: "").contains { $0.level == .unknown })
        XCTAssertFalse(mixed.filtered(level: .debug, query: "").contains { $0.level == .unknown })
    }

    // design 5: search is a case-insensitive substring
    func testFilterByQueryCaseInsensitive() {
        XCTAssertEqual(mixed.filtered(level: nil, query: "tunnel").count, 2)  // "tunnel up", "Tunnel down"
        XCTAssertEqual(mixed.filtered(level: nil, query: "TUNNEL").count, 2)
        XCTAssertEqual(mixed.filtered(level: nil, query: "name=nl").count, 2)
        XCTAssertTrue(mixed.filtered(level: nil, query: "absent").isEmpty)
        XCTAssertEqual(mixed.filtered(level: nil, query: "stack").map(\.level), [.unknown])
    }

    func testFilterCombinesLevelAndQuery() {
        let r = mixed.filtered(level: .info, query: "name=nl")
        XCTAssertEqual(r.map(\.level), [.info, .error])
        XCTAssertTrue(mixed.filtered(level: .error, query: "slow").isEmpty)
    }

    func testFilterKeepsOrder() {
        let texts = mixed.filtered(level: nil, query: "").map(\.text)
        XCTAssertEqual(texts, mixed.lines.map(\.text))
    }
}
