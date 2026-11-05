import Foundation

/// Log level of a line, parsed from `level=INFO` of the slog TextHandler.
/// Order: `debug` < `info` < `warn` < `error`; `unknown` has no level.
public enum LogLevel: Int, Comparable, Equatable, Sendable {
    case unknown = 0
    case debug
    case info
    case warn
    case error

    public static func < (a: LogLevel, b: LogLevel) -> Bool { a.rawValue < b.rawValue }
}

/// One log line without the trailing newline.
public struct LogLine: Equatable, Sendable {
    public var text: String
    public var level: LogLevel

    public init(text: String, level: LogLevel) {
        self.text = text
        self.level = level
    }
}

/// Tail of the engine log (design 5). The caller reads the file and feeds the
/// bytes here; the Kit does no I/O.
public struct LogTail: Sendable {
    /// Keep the last `maxLines` lines; first load reads at most `maxBytes`.
    public let maxBytes: Int
    public let maxLines: Int

    /// Offset in the file to read from next: the caller reads from here and
    /// calls `append`, which advances it by `data.count`. The caller may set it once
    /// before the first read to skip all but the last `maxBytes` of a large file.
    public var offset: UInt64

    /// Complete lines, oldest first, at most `maxLines`.
    public private(set) var lines: [LogLine]

    /// Bytes of an incomplete last line, held until its newline arrives.
    private var pending = Data()
    /// Some data has been appended since init or `reset`.
    private var started = false
    /// Dropping bytes up to the first newline (the chunk began mid-line).
    private var skippingPartial = false

    public init(maxBytes: Int = 256 * 1024, maxLines: Int = 2000) {
        self.maxBytes = maxBytes
        self.maxLines = maxLines
        self.offset = 0
        self.lines = []
    }

    /// Appends bytes read at `offset`. A trailing partial line is held back until
    /// its newline arrives; if the chunk starts mid-line (first read of a large
    /// file), the partial first line is dropped. Invalid UTF-8 is replaced.
    public mutating func append(_ data: Data) {
        var chunk = data
        if !started {
            started = true
            if offset > 0 { skippingPartial = true }
            if chunk.count > maxBytes {
                chunk = chunk.suffix(maxBytes)
                skippingPartial = true
            }
        }
        offset += UInt64(data.count)

        for byte in chunk {
            if byte != 0x0A {
                if !skippingPartial { pending.append(byte) }
                continue
            }
            if skippingPartial {
                skippingPartial = false
                continue
            }
            if pending.last == 0x0D { pending.removeLast() }
            let text = String(decoding: pending, as: UTF8.self)
            lines.append(LogLine(text: text, level: Self.level(of: text)))
            pending.removeAll(keepingCapacity: true)
        }
        if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
    }

    /// Starts over (file truncated or rotated): clears lines and the held-back
    /// partial line, sets `offset` to 0.
    public mutating func reset() {
        lines = []
        pending = Data()
        started = false
        skippingPartial = false
        offset = 0
    }

    /// Lines with `level >= level` (all when nil) whose text contains `query`
    /// (case-insensitive; empty matches all). `unknown` lines pass only when
    /// `level` is nil.
    public func filtered(level: LogLevel?, query: String) -> [LogLine] {
        lines.filter { line in
            if let level, line.level < level || line.level == .unknown { return false }
            return query.isEmpty || line.text.range(of: query, options: .caseInsensitive) != nil
        }
    }

    /// Level from the first ` level=XXX` token (slog TextHandler); `WARN+2` counts as WARN.
    private static func level(of text: String) -> LogLevel {
        var search = text.startIndex..<text.endIndex
        while let r = text.range(of: "level=", range: search) {
            if r.lowerBound == text.startIndex || text[text.index(before: r.lowerBound)] == " " {
                let rest = text[r.upperBound...]
                if rest.hasPrefix("DEBUG") { return .debug }
                if rest.hasPrefix("INFO") { return .info }
                if rest.hasPrefix("WARN") { return .warn }
                if rest.hasPrefix("ERROR") { return .error }
                return .unknown
            }
            search = r.upperBound..<text.endIndex
        }
        return .unknown
    }
}
