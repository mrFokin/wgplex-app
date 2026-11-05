import Foundation

/// The null result of `tunnel.disable`, `tunnel.disableAll`, `daemon.*`.
struct Empty: Decodable, Sendable {}

/// JSON-RPC 2.0 framing of a single (non-batch) call.
enum JSONRPC {
    /// Encodes `{"jsonrpc":"2.0","method":…,"params":…,"id":1}`; `params` is
    /// omitted when nil.
    static func encode(method: String, params: [String: String]? = nil) throws -> Data {
        var object: [String: Any] = ["jsonrpc": "2.0", "method": method, "id": 1]
        if let params {
            object["params"] = params
        }
        return try JSONSerialization.data(withJSONObject: object)
    }

    /// Decodes the reply body: its `result` into `T` (a null or absent
    /// result is fine for `Empty`), throws `RPCError.server` for an error
    /// object and `RPCError.transport` for anything malformed.
    static func decode<T: Decodable>(_: T.Type, from body: Data) throws -> T {
        let reply: Reply<T>
        do {
            reply = try JSONDecoder().decode(Reply<T>.self, from: body)
        } catch {
            throw RPCError.transport("bad JSON-RPC reply: \(describe(error))")
        }
        if let e = reply.error {
            throw RPCError.server(code: e.code, message: e.message, data: errorData(of: body))
        }
        if let result = reply.result {
            return result
        }
        if let empty = Empty() as? T {
            return empty
        }
        throw RPCError.transport("no result in the JSON-RPC reply")
    }

    private struct Reply<T: Decodable>: Decodable {
        var result: T?
        var error: ErrorObject?
    }

    private struct ErrorObject: Decodable {
        var code: Int
        var message: String
    }

    /// The raw JSON of `error.data`, nil when absent or null.
    private static func errorData(of body: Data) -> Data? {
        guard let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let error = root["error"] as? [String: Any],
              let data = error["data"], !(data is NSNull)
        else {
            return nil
        }
        return try? JSONSerialization.data(withJSONObject: data, options: .fragmentsAllowed)
    }

    private static func describe(_ error: any Error) -> String {
        if let e = error as? DecodingError {
            switch e {
            case .dataCorrupted(let c), .typeMismatch(_, let c), .valueNotFound(_, let c), .keyNotFound(_, let c):
                return c.debugDescription
            @unknown default:
                break
            }
        }
        return error.localizedDescription
    }
}
