import Foundation

/// One thing someone else left that may want the owner: a reply, a line on their page, a
/// label, a link, a name. A projection of the fold; nothing is stored for it.
public struct InboxItem: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        case reply, line, label, link, name
    }

    /// The event that made it, or the last of a group.
    public let id: ULID
    public let author: Author
    public let at: Date
    public let kind: Kind
    /// The line to open: the one replied under, the author's own line, the line marked.
    /// Nil when the item stands for several lines.
    public let entry: ULID?
    /// What the author did, as the page would say it: "replied", "wrote", "filed 3 lines
    /// under #nursery", "is called Moss now".
    public let what: String
    /// The words: the reply's, the line's. Empty when the item stands for several lines.
    public let text: String
    /// What it is about, when that is another line: the owner's line a reply sits under,
    /// the earlier line a link goes back to.
    public let about: String?
    /// The words ask something.
    public let asks: Bool
    /// The owner has replied since.
    public let answered: Bool
    /// The owner has not looked since it arrived.
    public let unread: Bool

    /// Asks and has not been answered: the part of the inbox that needs the owner.
    public var wantsYou: Bool { asks && !answered }
}

/// What happened in the notebook since one author last looked, said in a few lines so the
/// author knows where to go next. Replies first, since those are what it waits for; then
/// new lines, lines changed, things taken back, marks others left, names chosen.
public enum Inbox {
    /// The owner's inbox, newest first. Everything other authors left that the owner might
    /// want to see: replies under the owner's lines and in conversations the owner is in,
    /// lines on other pages, labels and links placed, names chosen. Unread is measured the
    /// way a grant's look is: the owner's last inbox visit recorded how long every event
    /// file was, so an event that reached this device late is still new.
    public static func items(files: [(file: String, events: [Event])], notebook: Notebook, calendar: Calendar) -> [InboxItem] {
        let owner = notebook.owner
        let look = notebook.visits.last { $0.author == owner && $0.read.what == .inbox }
        let seen = look?.read.seen ?? [:]

        func words(_ entry: Entry) -> String {
            let text = entry.text.replacingOccurrences(of: "\n", with: " ")
            return text.isEmpty ? "a photo" : text
        }
        func asks(_ text: String) -> Bool { text.contains("?") }

        struct LabelKey: Hashable {
            let author: Author
            let label: String
            let day: DayKey
        }
        struct LabelGroup {
            var last: Event
            var entries: [ULID] = []
            var unread = false
        }

        var items: [InboxItem] = []
        var labels: [LabelKey: LabelGroup] = [:]

        for (file, events) in files {
            let floor = seen[file] ?? 0
            for (index, event) in events.enumerated() where event.author != owner {
                let unread = index >= floor
                switch event.payload {
                case .noteAdd(let p):
                    guard let entry = notebook.entry(p.entry), let note = entry.notes.first(where: { $0.id == p.note }) else { continue }
                    let mine = entry.notes.filter { $0.author == owner }
                    // Under the owner's line, or in a conversation the owner is part of.
                    guard entry.author == owner || !mine.isEmpty else { continue }
                    items.append(InboxItem(
                        id: event.id, author: event.author, at: event.at, kind: .reply, entry: entry.id,
                        what: "replied", text: note.text, about: entry.author == owner ? words(entry) : nil,
                        asks: asks(note.text), answered: mine.contains { $0.id > note.id }, unread: unread))

                case .entryCreate(let p):
                    guard let entry = notebook.entry(p.entry) else { continue }
                    items.append(InboxItem(
                        id: event.id, author: event.author, at: event.at, kind: .line, entry: entry.id,
                        what: "wrote", text: words(entry), about: nil,
                        asks: asks(entry.text), answered: entry.notes.contains { $0.author == owner }, unread: unread))

                case .labelAttach(let p):
                    let label = p.label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    guard let entry = notebook.entry(p.entry), entry.labels.contains(label) else { continue }
                    let key = LabelKey(author: event.author, label: label, day: DayKey(event.at, calendar: calendar))
                    var group = labels[key] ?? LabelGroup(last: event)
                    if event.id > group.last.id { group.last = event }
                    if !group.entries.contains(entry.id) { group.entries.append(entry.id) }
                    group.unread = group.unread || unread
                    labels[key] = group

                case .linkAdd(let p):
                    guard let later = notebook.entry(p.later), let earlier = notebook.entry(p.earlier),
                          later.earlier.contains(where: { $0.earlier == p.earlier }) else { continue }
                    items.append(InboxItem(
                        id: event.id, author: event.author, at: event.at, kind: .link, entry: later.id,
                        what: p.closes ? "marked done" : "joined", text: words(later),
                        about: (p.closes ? "done by this: " : "carries on from: ") + words(earlier),
                        asks: false, answered: false, unread: unread))

                case .nameSet(let p):
                    let name = p.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty, notebook.name(of: event.author) == name else { continue }
                    items.append(InboxItem(
                        id: event.id, author: event.author, at: event.at, kind: .name, entry: nil,
                        what: "is called \(name) now", text: "", about: nil,
                        asks: false, answered: false, unread: unread))

                case .entryEdit, .entryDelete, .mediaAttach, .noteEdit, .noteRemove, .labelDetach, .linkRemove, .visit:
                    continue
                }
            }
        }

        for (key, group) in labels {
            let one = group.entries.count == 1 ? group.entries[0] : nil
            items.append(InboxItem(
                id: group.last.id, author: key.author, at: group.last.at, kind: .label, entry: one,
                what: one != nil ? "filed under #\(key.label)" : "filed \(group.entries.count) lines under #\(key.label)",
                text: one.flatMap { notebook.entry($0) }.map(words) ?? "", about: nil,
                asks: false, answered: false, unread: group.unread))
        }

        return items.sorted { $0.id > $1.id }
    }

    /// The receipt for the owner's look: how long every file was, so the next look starts
    /// after it, and how much was new.
    public static func look(files: [(file: String, events: [Event])], unread: Int) -> Payload.Visit {
        .init(what: .inbox, count: unread, seen: Dictionary(uniqueKeysWithValues: files.map { ($0.file, $0.events.count) }))
    }

    public struct Report: Sendable {
        /// How many things were worth a line.
        public let count: Int
        public let text: String
    }

    /// `fresh` is every event the author has not seen, by anyone else, oldest first.
    /// `all` is the whole log, for the facts a late event needs: whose note was taken back.
    public static func report(_ fresh: [Event], all: [Event], notebook: Notebook, me: Author, since: Date?, calendar: Calendar) -> Report {
        let noteAuthors: [ULID: Author] = all.reduce(into: [:]) { map, event in
            if case .noteAdd(let p) = event.payload { map[p.note] = event.author }
        }
        let gone: Set<ULID> = fresh.reduce(into: []) { set, event in
            if case .noteRemove(let p) = event.payload { set.insert(p.note) }
        }
        func who(_ author: Author) -> String { notebook.name(of: author) ?? author.rawValue }
        func words(_ id: ULID) -> String {
            guard let entry = notebook.entry(id) else { return "a line that is gone" }
            let text = entry.text.replacingOccurrences(of: "\n", with: " ")
            if text.isEmpty { return "a photo" }
            return text.count > 60 ? String(text.prefix(59)) + "…" : text
        }
        func place(_ id: ULID) -> String {
            guard let entry = notebook.entry(id) else { return "\(id)" }
            let whose = entry.author == me ? "your line" : entry.author == notebook.owner ? "the line" : "\(who(entry.author))'s line"
            return "\(whose) \(id) “\(words(id))”"
        }

        var replies: [String] = []
        var lines: [String] = []
        var changed: [String] = []
        var takenBack: [String] = []
        var marks: [String] = []
        var names: [String] = []

        for event in fresh {
            switch event.payload {
            case .noteAdd(let p):
                guard !gone.contains(p.note) else { continue }
                replies.append("\(who(event.author)) under \(place(p.entry)): \(p.text)")
            case .noteEdit(let p):
                guard !gone.contains(p.note), let entry = notebook.entries(of: notebook.owner).first(where: { $0.notes.contains { $0.id == p.note } })
                    ?? notebook.entries(of: me).first(where: { $0.notes.contains { $0.id == p.note } })
                else { continue }
                replies.append("\(who(event.author)) changed a reply under \(place(entry.id)): \(p.text)")
            case .entryCreate(let p):
                guard notebook.entry(p.entry) != nil else { continue }
                let by = event.author == notebook.owner ? "" : "  by \(who(event.author))"
                lines.append("\(p.entry)  \(DayKey(p.startedAt, calendar: calendar)) \(Projector.time(p.startedAt, calendar: calendar))  \(words(p.entry))\(by)")
            case .entryEdit(let p):
                guard notebook.entry(p.entry) != nil else { continue }
                changed.append("\(p.entry) now reads: \(words(p.entry))")
            case .entryDelete(let p):
                changed.append("\(p.entry) is gone")
            case .mediaAttach(let p):
                guard notebook.entry(p.entry) != nil else { continue }
                let kind = p.mime.hasPrefix("image") ? "a photo" : p.mime.hasPrefix("audio") ? "a voice note" : p.mime.hasPrefix("video") ? "a video" : "a file"
                changed.append("\(p.entry) got \(kind): \(words(p.entry))")
            case .noteRemove(let p):
                let whose = noteAuthors[p.note] == me ? "your note" : "a note"
                takenBack.append("\(who(event.author)) took back \(whose)")
            case .labelDetach(let p):
                takenBack.append("\(who(event.author)) took #\(p.label) off \(p.entry)")
            case .linkRemove(let p):
                takenBack.append("\(who(event.author)) took back the link from \(p.later) to \(p.earlier)")
            case .labelAttach(let p):
                marks.append("\(who(event.author)) filed \(p.entry) under #\(p.label)")
            case .linkAdd(let p):
                marks.append("\(who(event.author)) linked \(p.later) back to \(p.earlier)\(p.closes ? ", closing it" : "")")
            case .nameSet(let p):
                names.append("\(event.author) is called \(p.name) now")
            case .visit:
                continue
            }
        }

        let sections: [(String, [String])] = [
            ("Replies", replies), ("New lines", lines), ("Changed", changed),
            ("Taken back", takenBack), ("Marks", marks), ("Names", names),
        ]
        let count = sections.reduce(0) { $0 + $1.1.count }
        let when = since.map { "since \(Projector.moment($0, calendar: calendar))" } ?? "since the door was opened to you"
        guard count > 0 else { return Report(count: 0, text: "Nothing new \(when).") }
        var out = ["\(count) new thing\(count == 1 ? "" : "s") \(when)."]
        for (title, items) in sections where !items.isEmpty {
            out.append("")
            out.append("## \(title)")
            out.append(contentsOf: items)
        }
        return Report(count: count, text: out.joined(separator: "\n"))
    }
}
