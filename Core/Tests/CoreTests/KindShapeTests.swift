import XCTest
@testable import Core

/// What a kind of thing is: the facts its things have, in order, and how a thing's page
/// draws them.
final class KindShapeTests: XCTestCase {
    private var root: URL!
    private var store: FileStore!
    private let owner = Author(rawValue: "wiju")
    private let ids = ULIDGenerator()

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("shapes-\(ULID().string)", isDirectory: true)
        store = try FileStore.create(at: root, owner: owner)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func write(_ payload: (ULID) -> Payload, by author: Author, on device: DeviceID = "claude-code") throws -> ULID {
        let now = Date()
        let id = ids.next(at: now)
        try store.append(Event(id: id, author: author, device: device, at: now, payload: payload(id)))
        return id
    }

    private func door(_ author: Author = .dotto) -> Door {
        Door(store: store, grant: Grant(name: "Claude Code", author: author, device: "claude-code", createdAt: Date().addingTimeInterval(-3600)), calendar: .current)
    }

    private func tell(_ door: Door, _ tool: String, _ arguments: [String: Any] = [:]) throws -> String {
        let request: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": tool, "arguments": arguments]]
        let data = try XCTUnwrap(door.handle(try JSONSerialization.data(withJSONObject: request)))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return (((json["result"] as? [String: Any])?["content"] as? [[String: Any]]) ?? []).compactMap { $0["text"] as? String }.joined()
    }

    /// A paper's page shows what a paper has, in a paper's order, whatever order the facts
    /// were put on it in; what no shape names comes after, drawn by what it looks like.
    func testAThingIsDrawnByItsKindsShape() throws {
        let paper = try write({ .thingSet(.init(thing: $0, name: "More Is Different", kind: "paper")) }, by: .dotto)
        try write({ _ in .factSet(.init(on: paper, key: "source", value: .words("https://example.com/more.pdf"))) }, by: .dotto)
        try write({ _ in .factSet(.init(on: paper, key: "pages", value: .number(4, unit: nil))) }, by: .dotto)
        try write({ _ in .factSet(.init(on: paper, key: "when", value: .words("1972"))) }, by: .dotto)
        try write({ _ in .factSet(.init(on: paper, key: "about", value: .words("Each level of complexity has laws of its own."))) }, by: .dotto)
        try write({ _ in .factSet(.init(on: paper, key: "by", value: .words("P. W. Anderson"))) }, by: .dotto)
        try write({ _ in .factSet(.init(on: paper, key: "site", value: .words("https://example.com/anderson"))) }, by: .dotto)

        var notebook = try store.load()
        XCTAssertEqual(notebook.shape(of: "Paper")?.has.map(\.key), ["about", "by", "when", "source"], "the usual shape, until someone says otherwise")
        var drawn = notebook.drawn(try XCTUnwrap(notebook.thing(paper)))
        XCTAssertEqual(drawn.map(\.key), ["about", "by", "when", "source", "pages", "site"])
        XCTAssertEqual(drawn.map(\.what), [.text, .words, .words, .link, .number, .link])
        XCTAssertEqual(drawn.first?.says, "What it says and why it matters, in a few plain sentences.")

        // Another originator puts the same key later: one row, the newest word.
        try write({ _ in .factSet(.init(on: paper, key: "when", value: .words("August 1972"))) }, by: "friend")
        notebook = try store.load()
        drawn = notebook.drawn(try XCTUnwrap(notebook.thing(paper)))
        XCTAssertEqual(drawn.filter { $0.key == "when" }.map { $0.fact.value }, [.words("August 1972")])

        // A thing of a kind nobody has shaped is drawn by what its facts look like.
        let wine = try write({ .thingSet(.init(thing: $0, name: "Quinta do Crasto 2022", kind: "wine")) }, by: .dotto)
        try write({ _ in .factSet(.init(on: wine, key: "notes", value: .words(String(repeating: "Warm, dark fruit, a long finish. ", count: 4)))) }, by: .dotto)
        notebook = try store.load()
        XCTAssertNil(notebook.shape(of: "wine"))
        XCTAssertEqual(notebook.drawn(try XCTUnwrap(notebook.thing(wine))).map(\.what), [.text])
    }

    /// Anyone through the door says what a kind has; the newest word stands; only the owner
    /// drops it; in any order of arrival.
    func testAShapeIsSaidThroughTheDoorAndDroppedByTheOwner() throws {
        let said = try tell(door(), "set_shape", ["kind": "Wine", "has": [
            ["key": "about", "is": "text", "says": "What it tastes like."], ["key": "from", "is": "words"], ["key": "price", "is": "number"],
        ]])
        XCTAssertEqual(said, "A wine has: about, from, price. Every wine is drawn by it from now on.")
        XCTAssertTrue(try tell(door(), "set_shape", ["kind": "wine", "has": [["key": "a", "is": "poem"]]]).contains("what a is: text, words, link"))
        XCTAssertTrue(try tell(door(), "set_shape", ["kind": "wine", "has": [["key": "a", "is": "text"], ["key": "A", "is": "words"]]]).contains("each key once"))

        // A thing made of that kind is told what to fill; one of an unshaped kind is told so.
        let made = try tell(door(), "set_thing", ["name": "Quinta do Crasto 2022", "kind": "wine"])
        XCTAssertTrue(made.contains("A wine has, in order: about (text: What it tastes like.); from (words); price (number). Put them on it with set_fact"), made)
        XCTAssertTrue(try tell(door(), "set_thing", ["name": "Graphite", "kind": "element"]).contains("No shape says what a element has yet"))
        XCTAssertTrue(try tell(door(), "set_thing", ["name": "Stalingrad", "kind": "book"]).contains("A book has, in order: about"))

        let listed = try tell(door(), "list_shapes")
        XCTAssertTrue(listed.contains("wine  1 thing · said by dotto\n  about  text  What it tastes like.\n  from  words\n  price  number"), listed)
        XCTAssertTrue(listed.contains("book  1 thing · the usual shape"), listed)
        XCTAssertFalse(listed.contains("element"), "a kind nobody has shaped has no shape to list")

        // A friend says it again, with one more: that is what a wine has now.
        _ = try tell(door("friend"), "set_shape", ["kind": "wine", "has": [["key": "about", "is": "text"], ["key": "from", "is": "words"],
                                                                             ["key": "price", "is": "number"], ["key": "year", "is": "words"]]])
        // A stranger's word that it is dropped changes nothing; the owner's drops it, and a usual one too.
        try write({ _ in .shapeRemove(.init(kind: "wine")) }, by: "stranger")
        let events = try store.loadEvents()
        for order in [events, events.reversed(), events.shuffled()] {
            let notebook = Notebook(owner: owner, events: order)
            XCTAssertEqual(notebook.shape(of: "wine")?.has.map(\.key), ["about", "from", "price", "year"])
            XCTAssertEqual(notebook.shaper(of: "wine"), "friend")
        }
        try write({ _ in .shapeRemove(.init(kind: "wine")) }, by: owner, on: "phone")
        try write({ _ in .shapeRemove(.init(kind: "book")) }, by: owner, on: "phone")
        let notebook = try store.load()
        XCTAssertNil(notebook.shape(of: "wine"))
        XCTAssertNil(notebook.shape(of: "book"), "the owner drops a usual shape too")
        XCTAssertNotNil(notebook.shape(of: "paper"))
    }

    func testAShapeIsToldOfAndWrittenAndReadBack() throws {
        _ = try tell(door(), "whats_new")
        try write({ _ in .shapeSet(KindShape(kind: "Wine", has: [.init("about", .text), .init("from", .words)])) }, by: "friend")
        XCTAssertTrue(try tell(door(), "whats_new").contains("friend said what a wine has: about, from"))

        let event = Event(id: ULID(), author: .dotto, device: "claude-code", at: Date(),
                          payload: .shapeSet(KindShape(kind: "paper", has: [.init("about", .text, "What it says."), .init(key: "doi", is: "identifier")])))
        let json = try JSONLines.encode(event)
        XCTAssertTrue(json.contains("\"kind\":\"shape.set\""), json)
        let back = try JSONLines.decode(json)
        XCTAssertEqual(back, event)
        guard case .shapeSet(let shape) = back.payload else { return XCTFail() }
        XCTAssertEqual(shape.has.map(\.what), [.text, .words], "a kind of fact this build does not know is drawn as words, and kept as written")
        XCTAssertEqual(shape.has.last?.is, "identifier")
    }
}
