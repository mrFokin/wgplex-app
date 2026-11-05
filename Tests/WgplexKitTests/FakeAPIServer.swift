import Foundation
import XCTest

// Test support: canned replies, an HTTP framing helper and a fake daemon on a
// real unix socket (plan A1, decision 7). No network, no root.

/// What the fake daemon answers to one JSON-RPC request.
enum FakeReply: Sendable {
    /// HTTP 200 with a JSON-RPC result (`json` is raw JSON text).
    case result(String)
    /// HTTP 200 with a JSON-RPC error; `data` is raw JSON text or nil.
    case error(code: Int, message: String = "error", data: String? = nil)
    /// A bare HTTP reply with the given status and body.
    case http(status: Int, body: String)
    /// HTTP 200 with a result and no Content-Length (body runs to EOF).
    case resultUntilEOF(String)
    /// Never answers (keeps the connection open).
    case hang
}

/// Splits a raw HTTP request into head and body.
func splitHTTP(_ data: Data) -> (head: String, body: Data)? {
    guard let r = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
    let head = String(decoding: data[data.startIndex..<r.lowerBound], as: UTF8.self)
    return (head, Data(data[r.upperBound...]))
}

/// The JSON body of a raw HTTP request.
func rpcBody(of request: Data) -> [String: Any]? {
    guard let (_, body) = splitHTTP(request) else { return nil }
    return try? JSONSerialization.jsonObject(with: body) as? [String: Any]
}

/// Method of the JSON-RPC request carried by a raw HTTP request.
func rpcMethod(of request: Data) -> String? {
    rpcBody(of: request)?["method"] as? String
}

/// Full HTTP response for `reply`, echoing the id of `request`.
func httpResponse(for reply: FakeReply, request: Data) -> Data {
    var idText = "1"
    if let id = rpcBody(of: request)?["id"] {
        if let n = id as? Int { idText = String(n) } else if let s = id as? String { idText = "\"\(s)\"" }
    }
    func http(_ status: Int, _ body: String, length: Bool = true) -> Data {
        var head = "HTTP/1.1 \(status) X\r\nContent-Type: application/json\r\n"
        if length { head += "Content-Length: \(body.utf8.count)\r\n" }
        head += "Connection: close\r\n\r\n"
        return Data((head + body).utf8)
    }
    switch reply {
    case .result(let json):
        return http(200, "{\"jsonrpc\":\"2.0\",\"id\":\(idText),\"result\":\(json)}")
    case .resultUntilEOF(let json):
        return http(200, "{\"jsonrpc\":\"2.0\",\"id\":\(idText),\"result\":\(json)}", length: false)
    case .error(let code, let message, let data):
        let d = data.map { ",\"data\":\($0)" } ?? ""
        return http(
            200, "{\"jsonrpc\":\"2.0\",\"id\":\(idText),\"error\":{\"code\":\(code),\"message\":\"\(message)\"\(d)}}")
    case .http(let status, let body):
        return http(status, body)
    case .hang:
        return Data()
    }
}

/// Records the raw requests that reach a `roundTrip` closure.
final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Data] = []
    func add(_ d: Data) { lock.lock(); items.append(d); lock.unlock() }
    var requests: [Data] { lock.lock(); defer { lock.unlock() }; return items }
    var methods: [String] { requests.compactMap(rpcMethod(of:)) }
}

/// A fake daemon on a real unix socket in /tmp (short path), served from
/// background threads. One request per connection, closed after the reply.
final class FakeAPIServer: @unchecked Sendable {
    let path: String
    private let handler: @Sendable (String) -> FakeReply
    private let recorder = Recorder()
    private let lock = NSLock()
    private var stopped = false
    private let listenFD: Int32
    private let acceptDone = DispatchSemaphore(value: 0)

    var requests: [Data] { recorder.requests }
    var methods: [String] { recorder.methods }

    /// `handler` maps a JSON-RPC method name to the reply.
    init(handler: @escaping @Sendable (String) -> FakeReply) throws {
        self.handler = handler
        let p = "/tmp/wgx-\(UUID().uuidString.prefix(8)).sock"
        path = p
        unlink(p)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw NSError(domain: "FakeAPIServer", code: Int(errno)) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(p.utf8)
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            for (i, b) in bytes.enumerated() { buf[i] = b }
            buf[bytes.count] = 0
        }
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard rc == 0, listen(fd, 16) == 0 else {
            close(fd)
            throw NSError(domain: "FakeAPIServer", code: Int(errno))
        }
        listenFD = fd
        Thread.detachNewThread { [self] in acceptLoop() }
    }

    private var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }

    private func acceptLoop() {
        while !isStopped {
            var p = pollfd(fd: listenFD, events: Int16(POLLIN), revents: 0)
            guard poll(&p, 1, 50) > 0 else { continue }
            let c = accept(listenFD, nil, nil)
            if c < 0 { continue }
            var one: Int32 = 1
            setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
            Thread.detachNewThread { [self] in serve(c) }
        }
        acceptDone.signal()
    }

    private func serve(_ fd: Int32) {
        defer { close(fd) }
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while !isStopped {
            if let (head, body) = splitHTTP(data) {
                var need = 0
                for line in head.components(separatedBy: "\r\n") where line.lowercased().hasPrefix("content-length:") {
                    need = Int(line.dropFirst(15).trimmingCharacters(in: .whitespaces)) ?? 0
                }
                if body.count >= need { break }
            }
            var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard poll(&p, 1, 50) > 0 else { continue }
            let n = read(fd, &buf, buf.count)
            if n <= 0 { return }
            data.append(contentsOf: buf[0..<n])
        }
        recorder.add(data)
        let reply = handler(rpcMethod(of: data) ?? "")
        if case .hang = reply {
            while !isStopped { usleep(20_000) }
            return
        }
        let out = httpResponse(for: reply, request: data)
        out.withUnsafeBytes { raw in
            var off = 0
            while off < raw.count {
                let n = write(fd, raw.baseAddress! + off, raw.count - off)
                if n <= 0 { return }
                off += n
            }
        }
    }

    func stop() {
        lock.lock()
        let already = stopped
        stopped = true
        lock.unlock()
        if already { return }
        acceptDone.wait()
        close(listenFD)
        unlink(path)
    }

    deinit { stop() }
}
