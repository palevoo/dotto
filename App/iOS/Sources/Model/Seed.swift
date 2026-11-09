#if DEBUG
import Core
import UIKit

/// Lines for the UI tests, made on launch when asked for with `-uitest-seed-photos`: one
/// line with two photos of printed words, so the viewer has pages to turn and words for
/// Live Text to find. Debug builds only; made once per notebook.
@MainActor
enum Seed {
    static let words = "Two pages from a book, for the viewer"
    static let pages = [
        "Writing costs nothing. One gesture, no categories, no decisions, no audience.",
        "Meaning comes later. What a line is, what it connects to, what it should trigger, is decided after it is written.",
    ]

    static func runIfAsked(_ model: NotebookModel) async {
        guard ProcessInfo.processInfo.arguments.contains("-uitest-seed-photos") else { return }
        let line: ULID
        if let existing = model.notebook.entries.first(where: { $0.text == words }) {
            line = existing.id
        } else {
            for page in pages {
                await model.addPhoto(render(page))
            }
            model.draftText = words
            guard let made = model.commitDraft() else { return }
            line = made
        }
        let seed = Author(rawValue: "seed")
        // A tag on the line, placed by another originator, as the owner never files.
        if model.notebook.entry(line)?.labels.contains("book") != true {
            try? model.store.append(Event(id: ULID(), author: seed, device: model.device, at: Date(),
                                          payload: .labelAttach(.init(entry: line, label: "book"))))
        }
        // A second line, and a note under the first that cites it.
        let second: ULID
        if let existing = model.notebook.entries.first(where: { $0.text == cited }) {
            second = existing.id
        } else {
            model.draftText = cited
            guard let made = model.commitDraft() else { return }
            second = made
        }
        if model.notebook.entry(line)?.notes.contains(where: { !$0.cites.isEmpty }) != true {
            let note = ULID()
            try? model.store.append(Event(id: note, author: seed, device: model.device, at: Date(),
                                          payload: .noteAdd(.init(entry: line, note: note, text: citing))))
            try? model.store.append(Event(id: ULID(), author: seed, device: model.device, at: Date(),
                                          payload: .link(.init(from: note, to: second))))
        }
        // A thing the second line belongs to, with its state, and a fact on the first line.
        if !model.notebook.allThings.contains(where: { $0.name == thing }) {
            let fig = ULID()
            try? model.store.append([
                Event(id: fig, author: seed, device: model.device, at: Date(), payload: .thingSet(.init(thing: fig, name: thing, kind: "plant"))),
                Event(id: ULID(), author: seed, device: model.device, at: Date(), payload: .link(.init(from: second, to: fig))),
                Event(id: ULID(), author: seed, device: model.device, at: Date(), payload: .factSet(.init(on: fig, key: "state", value: .words("potted")))),
                Event(id: ULID(), author: seed, device: model.device, at: Date(), payload: .factSet(.init(on: line, key: "pages", value: .number(2, unit: nil)))),
            ])
        }
        // A grant for the seed, so a loop can run as it, and a loop it proposes.
        let seedGrant = model.notebook.allGrants.first { $0.author == seed } ?? Grant(name: "Seed", author: seed, device: "seed")
        if !model.notebook.allGrants.contains(where: { $0.author == seed }) {
            try? model.store.append(Event(id: ULID(), author: model.store.manifest.owner, device: model.device, at: Date(),
                                          payload: .grantCreate(seedGrant.create)))
        }
        if model.notebook.loopProposals.isEmpty, !model.notebook.allLoops.contains(where: { $0.name == proposal }) {
            let id = ULID()
            try? model.store.append(Event(id: id, author: seed, device: model.device, at: Date(),
                                          payload: .loopPropose(.init(loop: id, name: proposal, grant: seedGrant.id, wake: "line",
                                                                      brief: "Each walk as a line, in Health's name."))))
        }
        // A walk, as Health would put it on the owner's page under its own name.
        if !model.notebook.entries.contains(where: { $0.text == walk }) {
            let health = NotebookModel.health
            var events: [Event] = []
            if model.notebook.name(of: health) == nil {
                events.append(Event(id: ULID(), author: health, device: model.device, at: Date(), payload: .nameSet(.init(name: "Health"))))
            }
            let id = ULID()
            events.append(Event(id: id, author: health, device: model.device, at: Date(),
                                payload: .entryCreate(.init(entry: id, text: walk, startedAt: Date(), page: model.store.manifest.owner))))
            try? model.store.append(events)
        }
        model.reload()
    }

    static let walk = "Walk, 3.1 km, 41 min"
    static let thing = "the fig"
    static let proposal = "Bring the walks"
    static let cited = "Meaning comes later, says the second page"
    static let citing = "Both pages say the same; see the second."

    /// A page of a book: black serif on white, large enough for Live Text.
    static func render(_ text: String) -> Data {
        let size = CGSize(width: 1200, height: 1600)
        return UIGraphicsImageRenderer(size: size).jpegData(withCompressionQuality: 0.9) { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 18
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.serif(56), .foregroundColor: UIColor.black, .paragraphStyle: paragraph,
            ]
            (text as NSString).draw(in: CGRect(x: 120, y: 220, width: 960, height: 1200), withAttributes: attributes)
        }
    }
}
#endif
