import ImageIO
import XCTest
@testable import Core

final class DoorTests: XCTestCase {
    var root: URL!
    var store: FileStore!
    var grant: Grant!
    var door: Door!
    var wall: ULID!
    let generator = ULIDGenerator()

    var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("door-tests-\(UUID().uuidString)", isDirectory: true)
        store = try FileStore.create(at: root, owner: "me")
        let at = Date(timeIntervalSince1970: 1_793_610_840) // 2026-11-02 09:14 UTC
        wall = generator.next(at: at)
        try store.append(Event(id: wall, author: "me", device: "iphone", at: at,
                               payload: .entryCreate(.init(entry: wall, text: "Camera is a black screen", startedAt: at))))
        let earlier = at.addingTimeInterval(-86_400 * 3)
        let old = generator.next(at: earlier)
        try store.append(Event(id: old, author: "me", device: "iphone", at: earlier,
                               payload: .entryCreate(.init(entry: old, text: "Olives in", startedAt: earlier))))
        grant = Grant(name: "Claude Code on this Mac", author: .weeju, device: "mac-door")
        door = Door(store: store, grant: grant, calendar: utc)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func rpc(_ method: String, _ params: [String: Any] = [:], id: Any = 1) throws -> [String: Any]? {
        let request: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method, "params": params]
        let data = try JSONSerialization.data(withJSONObject: request)
        guard let response = door.handle(data) else { return nil }
        return try JSONSerialization.jsonObject(with: response) as? [String: Any]
    }

    func text(_ response: [String: Any]?) -> String {
        let result = response?["result"] as? [String: Any]
        let content = result?["content"] as? [[String: Any]]
        return content?.first?["text"] as? String ?? ""
    }

    func testInitializeAndListTools() throws {
        let initialized = try rpc("initialize", ["protocolVersion": "2025-03-26", "capabilities": [:], "clientInfo": ["name": "test"]])
        let result = initialized?["result"] as? [String: Any]
        XCTAssertEqual(result?["protocolVersion"] as? String, "2025-03-26")
        XCTAssertEqual((result?["serverInfo"] as? [String: Any])?["name"] as? String, "Margin")

        let tools = (try rpc("tools/list")?["result"] as? [String: Any])?["tools"] as? [[String: Any]]
        XCTAssertEqual(tools?.map { $0["name"] as? String }, ["read_days", "list_lines", "read_photo", "add_note", "set_label"])
    }

    func testEveryReadLeavesAReceipt() throws {
        _ = try rpc("tools/call", ["name": "read_days", "arguments": ["since": "2026-11-01"]])
        _ = try rpc("tools/call", ["name": "list_lines", "arguments": ["label": "Bug"]])
        let notebook = try store.load()
        XCTAssertEqual(notebook.visits.map(\.what), ["read 1 line since 2026-11-01", "read 0 lines under #bug"])
        XCTAssertEqual(notebook.visits.first?.author, .weeju)
        XCTAssertEqual(notebook.trail.map(\.what), notebook.visits.map(\.what))

        // The wall line is on 2026-11-02, so the first read took it in; the olives line is older.
        let wallReads = notebook.reads(of: notebook.entry(wall)!, calendar: utc)
        XCTAssertEqual(wallReads.count, 1)
        let olives = notebook.entries.first { $0.text == "Olives in" }!
        XCTAssertTrue(notebook.reads(of: olives, calendar: utc).isEmpty)

        // The whole folder is still two files: the owner's and the grant's.
        XCTAssertEqual(try store.eventFiles().map(\.lastPathComponent), ["me.iphone.jsonl", "weeju.mac-door.jsonl"])
    }

    func testReadPhotoHandsBackASmallJPEG() throws {
        let hash = try store.storeMedia(Self.jpeg(width: 3000, height: 2000), fileExtension: "jpg")
        try store.append(Event(id: generator.next(), author: "me", device: "iphone", at: Date(),
                               payload: .mediaAttach(.init(entry: wall, hash: hash, mime: "image/jpeg", width: 3000, height: 2000))))

        let response = try rpc("tools/call", ["name": "read_photo", "arguments": ["entry": wall.string]])
        let content = ((response?["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first
        XCTAssertEqual(content?["type"] as? String, "image")
        XCTAssertEqual(content?["mimeType"] as? String, "image/jpeg")
        let data = Data(base64Encoded: content?["data"] as? String ?? "")!
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        XCTAssertEqual(properties?[kCGImagePropertyPixelWidth] as? Int, Door.photoSide)

        let notebook = try store.load()
        XCTAssertEqual(notebook.visits.last?.read.hash, hash)
        XCTAssertEqual(notebook.reads(of: notebook.entry(wall)!, calendar: utc).count, 1)

        let missing = try rpc("tools/call", ["name": "read_photo", "arguments": ["entry": wall.string, "hash": "nope"]])
        XCTAssertTrue(text(missing).contains("No photo"))
    }

    /// A flat grey JPEG of the given size, made with ImageIO.
    static func jpeg(width: Int, height: Int) throws -> Data {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = context.makeImage()!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    func testNotificationsGetNoReply() throws {
        let data = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "method": "notifications/initialized"])
        XCTAssertNil(door.handle(data))
    }

    func testUnknownMethodAndBadJSON() throws {
        let error = try rpc("nope")?["error"] as? [String: Any]
        XCTAssertEqual(error?["code"] as? Int, -32601)
        let garbage = door.handle(Data("not json".utf8))
        let parsed = try JSONSerialization.jsonObject(with: garbage!) as? [String: Any]
        XCTAssertEqual((parsed?["error"] as? [String: Any])?["code"] as? Int, -32700)
    }

    func testReadAndListWithSinceAndLabel() throws {
        let all = text(try rpc("tools/call", ["name": "read_days", "arguments": [:]]))
        XCTAssertTrue(all.contains("# 2026-10-30"))
        XCTAssertTrue(all.contains("Camera is a black screen"))

        let recent = text(try rpc("tools/call", ["name": "list_lines", "arguments": ["since": "2026-11-01"]]))
        XCTAssertTrue(recent.hasPrefix(wall.string))
        XCTAssertFalse(recent.contains("Olives"))

        _ = try rpc("tools/call", ["name": "set_label", "arguments": ["entry": wall.string, "label": "Margin"]])
        let filed = text(try rpc("tools/call", ["name": "list_lines", "arguments": ["label": "margin"]]))
        XCTAssertTrue(filed.contains("#margin"))
        XCTAssertFalse(filed.contains("Olives"))

        _ = try rpc("tools/call", ["name": "set_label", "arguments": ["entry": wall.string, "label": "margin", "on": false]])
        XCTAssertEqual(text(try rpc("tools/call", ["name": "list_lines", "arguments": ["label": "margin"]])), "No lines.")
    }

    func testNoteLandsInTheGrantsOwnFile() throws {
        let reply = text(try rpc("tools/call", ["name": "add_note", "arguments": ["entry": wall.string, "text": "Rebuilt the camera on AVFoundation."]]))
        XCTAssertTrue(reply.contains("weeju"))
        XCTAssertEqual(try store.eventFiles().map(\.lastPathComponent), ["me.iphone.jsonl", "weeju.mac-door.jsonl"])
        let notebook = try store.load()
        XCTAssertEqual(notebook.entry(wall)?.notes.first?.text, "Rebuilt the camera on AVFoundation.")
        XCTAssertEqual(notebook.entry(wall)?.notes.first?.author, .weeju)
    }

    func testScopesAndMissingLines() throws {
        let readOnly = Grant(name: "Reader", author: "friend", device: "x", writesNotes: false, writesLabels: false)
        door = Door(store: store, grant: readOnly, calendar: utc)
        let refused = try rpc("tools/call", ["name": "add_note", "arguments": ["entry": wall.string, "text": "hi"]])
        XCTAssertEqual((refused?["result"] as? [String: Any])?["isError"] as? Bool, true)
        XCTAssertTrue(text(refused).contains("may not write notes"))

        door = Door(store: store, grant: grant, calendar: utc)
        let missing = try rpc("tools/call", ["name": "add_note", "arguments": ["entry": ULID().string, "text": "hi"]])
        XCTAssertTrue(text(missing).contains("No line with id"))
        let badDay = try rpc("tools/call", ["name": "read_days", "arguments": ["since": "yesterday"]])
        XCTAssertTrue(text(badDay).contains("Not a day"))
    }

    func testRouterRefusesWithoutTheKey() throws {
        let router = DoorRouter(calendar: utc) { [store, grant] key in
            key == grant!.key ? (store!, grant!) : nil
        }
        let body = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": "ping"])

        XCTAssertEqual(router.respond(HTTPRequest(method: "POST", path: "/mcp", headers: [:], body: body)).status, 401)
        XCTAssertEqual(router.respond(HTTPRequest(method: "POST", path: "/mcp", headers: ["authorization": "Bearer wrong"], body: body)).status, 401)
        XCTAssertEqual(router.respond(HTTPRequest(method: "GET", path: "/mcp", headers: [:], body: Data())).status, 405)
        XCTAssertEqual(router.respond(HTTPRequest(method: "POST", path: "/other", headers: [:], body: body)).status, 404)

        let ok = router.respond(HTTPRequest(method: "POST", path: "/mcp", headers: ["authorization": "Bearer \(grant.key)"], body: body))
        XCTAssertEqual(ok.status, 200)
        XCTAssertEqual(ok.headers["Content-Type"], "application/json")

        let notification = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "method": "notifications/initialized"])
        XCTAssertEqual(router.respond(HTTPRequest(method: "POST", path: "/mcp", headers: ["authorization": "Bearer \(grant.key)"], body: notification)).status, 202)
    }

    func testServerOverLoopback() async throws {
        let router = DoorRouter(calendar: utc) { [store, grant] key in
            key == grant!.key ? (store!, grant!) : nil
        }
        let server = try DoorServer { router.respond($0) }
        let port = try await server.start()
        defer { server.stop() }
        XCTAssertGreaterThan(port, 0)

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/mcp")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(grant.key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": 7, "method": "tools/call",
            "params": ["name": "list_lines", "arguments": ["since": "2026-11-01"]],
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["id"] as? Int, 7)
        XCTAssertTrue(text(object).contains("Camera is a black screen"))

        request.setValue("Bearer nope", forHTTPHeaderField: "Authorization")
        let (_, refused) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((refused as? HTTPURLResponse)?.statusCode, 401)
    }

    func testGrantKeysAreLongAndDistinct() {
        let a = Grant.makeKey(), b = Grant.makeKey()
        XCTAssertEqual(a.count, 43)
        XCTAssertNotEqual(a, b)
        XCTAssertFalse(a.contains("+") || a.contains("/") || a.contains("="))
    }
}
