import Foundation
@testable import Core

extension Author {
    /// Another originator, for a test that needs someone beside the owner and dotto.
    static let moss: Author = "moss"
}

extension DoorRouter {
    /// One message through the router, as a client posts it.
    func post(_ message: [String: Any], key: String, session: String? = nil, headers: [String: String] = [:]) -> HTTPResponse {
        var all = headers
        all["authorization"] = "Bearer \(key)"
        if let session { all["mcp-session-id"] = session }
        let body = try! JSONSerialization.data(withJSONObject: message)
        return respond(HTTPRequest(method: "POST", path: path, headers: all, body: body))
    }

    /// Begins a session as a client does, and gives back the id the door handed it.
    func begin(key: String, headers: [String: String] = [:]) -> String? {
        let hello: [String: Any] = ["jsonrpc": "2.0", "id": 0, "method": "initialize", "params": ["protocolVersion": "2025-06-18"]]
        return post(hello, key: key, headers: headers).headers["Mcp-Session-Id"]
    }
}
