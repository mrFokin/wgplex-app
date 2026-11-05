import Foundation
import Network

/// Byte transport to the daemon over its unix socket (Network.framework).
public final class UnixTransport: Sendable {
    let path: String

    /// A transport to the socket at `path`.
    public init(path: String) {
        self.path = path
    }

    /// One connection per call: sends `request`, reads the reply until EOF.
    /// Throws `RPCError.unavailable` for a missing/unanswered socket, a
    /// timeout and a path of 104 bytes or more (never traps).
    public func roundTrip(_ request: Data, timeout: TimeInterval) async throws -> Data {
        // NWEndpoint.unix traps on a path over sun_path (104 bytes).
        guard path.utf8.count < 104 else {
            throw RPCError.unavailable("socket path is longer than 103 bytes: \(path)")
        }
        return try await Exchange(path: path).run(request, timeout: timeout)
    }
}

/// Bounds the reply read from the daemon.
private let maxReply = 16 << 20

/// One connection of `UnixTransport.roundTrip`. All mutable state lives on
/// `queue`; the continuation is resumed exactly once by `finish`, which also
/// cancels the connection.
private final class Exchange: @unchecked Sendable {
    private let queue = DispatchQueue(label: "io.github.mrfokin.wgplex.transport")
    private let path: String
    private let connection: NWConnection
    private var continuation: CheckedContinuation<Data, any Error>?
    private var done = false
    private var reply = Data()
    private var timer: DispatchWorkItem?
    /// The request is out: from now on the pending receive ends the exchange.
    private var sent = false

    init(path: String) {
        self.path = path
        connection = NWConnection(to: .unix(path: path), using: .tcp)
    }

    func run(_ request: Data, timeout: TimeInterval) async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { c in
                queue.async { self.start(c, request, timeout) }
            }
        } onCancel: {
            queue.async { self.finish(.failure(CancellationError())) }
        }
    }

    private func start(_ c: CheckedContinuation<Data, any Error>, _ request: Data, _ timeout: TimeInterval) {
        if done {
            // Cancelled before the start.
            c.resume(throwing: CancellationError())
            return
        }
        continuation = c
        connection.stateUpdateHandler = { [self] state in
            switch state {
            case .ready:
                send(request)
            case .waiting(let error):
                finish(.failure(RPCError.unavailable(reason(error, path))))
            case .failed(let error):
                // After the send the pending receive still gets what has
                // arrived before an abrupt close and ends the exchange itself.
                if !sent {
                    fail(error)
                }
            default:
                break
            }
        }
        // Weak: a cancelled work item stays on the queue until its deadline
        // and must not keep the exchange and its reply alive till then.
        let timer = DispatchWorkItem { [weak self] in
            self?.finish(.failure(RPCError.unavailable("no reply within \(Int(timeout)) s")))
        }
        self.timer = timer
        queue.asyncAfter(deadline: .now() + timeout, execute: timer)
        connection.start(queue: queue)
    }

    private func send(_ request: Data) {
        sent = true
        // A send error is not final: the peer may have read the request and
        // closed with the reply already buffered; receive tells.
        connection.send(content: request, completion: .contentProcessed { [self] _ in
            receive()
        })
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 << 10) { [self] data, _, isComplete, error in
            if let data {
                reply.append(data)
            }
            if reply.count > maxReply {
                finish(.failure(RPCError.transport("reply over 16 MiB")))
            } else if let error {
                fail(error)
            } else if isComplete && reply.isEmpty {
                // Closed without a byte of reply: the daemon went away.
                finish(.failure(RPCError.unavailable("the daemon closed the connection without a reply")))
            } else if isComplete {
                finish(.success(reply))
            } else {
                receive()
            }
        }
    }

    /// Ends the exchange on a connection error: after a part of the reply
    /// the error is EOF (an abrupt close of the peer), before it
    /// `RPCError.unavailable`. `HTTP.body` catches a truncated reply.
    private func fail(_ error: NWError) {
        if reply.isEmpty {
            finish(.failure(RPCError.unavailable(reason(error, path))))
        } else {
            finish(.success(reply))
        }
    }

    private func finish(_ result: Result<Data, any Error>) {
        guard !done else {
            return
        }
        done = true
        timer?.cancel()
        timer = nil
        connection.stateUpdateHandler = nil
        connection.cancel()
        continuation?.resume(with: result)
        continuation = nil
        reply = Data()
    }
}

/// The text of a connection error for `RPCError.unavailable`.
private func reason(_ error: NWError, _ path: String) -> String {
    switch error {
    case .posix(.ENOENT):
        return "no socket at \(path)"
    case .posix(.ECONNREFUSED):
        return "nobody answers on the socket"
    case .posix(let code):
        return String(cString: strerror(code.rawValue))
    default:
        return error.localizedDescription
    }
}
