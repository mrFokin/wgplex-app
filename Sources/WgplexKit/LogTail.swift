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
    /// calls `append`, which advances it by `data.count`.
    public private(set) var offset: UInt64

    /// Complete lines, oldest first, at most `maxLines`.
    public private(set) var lines: [LogLine]

    public init(maxBytes: Int = 256 * 1024, maxLines: Int = 2000) {
        fatalError("not implemented")
    }

    /// Appends bytes read at `offset`. A trailing partial line is held back until
    /// its newline arrives; if the chunk starts mid-line (first read of a large
    /// file), the partial first line is dropped. Invalid UTF-8 is replaced.
    public mutating func append(_ data: Data) {
        fatalError("not implemented")
    }

    /// Starts over (file truncated or rotated): clears lines and the held-back
    /// partial line, sets `offset` to 0.
    public mutating func reset() {
        fatalError("not implemented")
    }

    /// Lines with `level >= level` (all when nil) whose text contains `query`
    /// (case-insensitive; empty matches all). `unknown` lines pass only when
    /// `level` is nil.
    public func filtered(level: LogLevel?, query: String) -> [LogLine] {
        fatalError("not implemented")
    }
}
