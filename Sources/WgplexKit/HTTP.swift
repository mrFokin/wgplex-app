import Foundation

/// The minimal HTTP/1.1 client side of a JSON-RPC call.
enum HTTP {
    /// Serializes `POST /rpc HTTP/1.1` with `Host`, `Content-Type:
    /// application/json`, `Content-Length` and `Connection: close`,
    /// followed by `body`.
    static func request(body: Data) -> Data {
        let head = "POST /rpc HTTP/1.1\r\n"
            + "Host: localhost\r\n"
            + "Content-Type: application/json\r\n"
            + "Content-Length: \(body.count)\r\n"
            + "Connection: close\r\n"
            + "\r\n"
        return Data(head.utf8) + body
    }

    /// Parses a full response read until EOF: the status line, headers
    /// (case-insensitive names) and the body by `Content-Length`, chunked
    /// encoding or up to EOF. A status other than 200 throws
    /// `RPCError.transport` with the trimmed body; a malformed response too.
    static func body(of response: Data) throws -> Data {
        let bytes = [UInt8](response)
        guard let headEnd = find(crlfcrlf, in: bytes, from: 0) else {
            throw RPCError.transport("no end of HTTP headers")
        }
        let lines = String(decoding: bytes[0..<headEnd], as: UTF8.self)
            .components(separatedBy: "\r\n")
        let status = try parseStatus(lines[0])

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else {
                throw RPCError.transport("bad HTTP header line")
            }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        let rest = Array(bytes[(headEnd + 4)...])
        let body: [UInt8]
        if let te = headers["transfer-encoding"], te.lowercased().contains("chunked") {
            body = try dechunk(rest)
        } else if let cl = headers["content-length"] {
            guard let n = Int(cl), n >= 0 else {
                throw RPCError.transport("bad Content-Length: \(cl)")
            }
            guard rest.count >= n else {
                throw RPCError.transport("body shorter than Content-Length: \(rest.count) of \(n) bytes")
            }
            body = Array(rest[0..<n])
        } else {
            body = rest
        }

        guard status == 200 else {
            let text = String(decoding: body, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw RPCError.transport("HTTP \(status)" + (text.isEmpty ? "" : ": \(text)"))
        }
        return Data(body)
    }

    private static let crlf: [UInt8] = [13, 10]
    private static let crlfcrlf: [UInt8] = [13, 10, 13, 10]

    /// The status code of `HTTP/1.x <code> <reason>`.
    private static func parseStatus(_ line: String) throws -> Int {
        let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2, parts[0].hasPrefix("HTTP/1."), parts[1].count == 3,
              let code = Int(parts[1])
        else {
            throw RPCError.transport("bad HTTP status line")
        }
        return code
    }

    /// Decodes a chunked body: `<hex size>[;ext]\r\n<data>\r\n` up to the
    /// zero-size chunk; trailers after it are skipped.
    private static func dechunk(_ b: [UInt8]) throws -> [UInt8] {
        var out: [UInt8] = []
        var pos = 0
        while true {
            guard let eol = find(crlf, in: b, from: pos) else {
                throw RPCError.transport("truncated chunked body")
            }
            var line = String(decoding: b[pos..<eol], as: UTF8.self)
            if let semi = line.firstIndex(of: ";") {
                line = String(line[..<semi])
            }
            line = line.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, line.allSatisfy(\.isHexDigit), let size = Int(line, radix: 16) else {
                throw RPCError.transport("bad chunk size")
            }
            pos = eol + 2
            if size == 0 {
                return out
            }
            guard size <= b.count - pos - 2 else {
                throw RPCError.transport("truncated chunked body")
            }
            out.append(contentsOf: b[pos..<(pos + size)])
            pos += size
            guard b[pos] == 13, b[pos + 1] == 10 else {
                throw RPCError.transport("no CRLF after a chunk")
            }
            pos += 2
        }
    }

    /// The index of the first occurrence of `needle` in `b` at or after `from`.
    private static func find(_ needle: [UInt8], in b: [UInt8], from: Int) -> Int? {
        guard b.count >= needle.count, from <= b.count - needle.count else {
            return nil
        }
        for i in from...(b.count - needle.count) where b[i] == needle[0] {
            if b[i..<(i + needle.count)].elementsEqual(needle) {
                return i
            }
        }
        return nil
    }
}
