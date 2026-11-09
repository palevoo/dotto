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
    /// Everything a grant has not seen, by anyone else, oldest first, and when it last looked.
    /// After the counts its last look took, file by file, so a file that grew late still
    /// counts; on the first look, since the grant last read anything, or since it was made.
    /// The same cursor whether the door answers whats_new or the reader asks whether to wake.
    public static func fresh(files: [(file: String, events: [Event])], notebook: Notebook, grant: Grant) -> (events: [Event], since: Date?) {
        let me = grant.author
        let last = notebook.visits.last { $0.author == me && $0.read.what == .inbox && $0.read.seen != nil }
        var fresh: [Event] = []
        if let seen = last?.read.seen {
            for (file, events) in files {
                fresh.append(contentsOf: events.dropFirst(min(seen[file] ?? 0, events.count)))
            }
        } else {
            let floor = notebook.visits.last { $0.author == me }?.id
            for (_, events) in files {
                fresh.append(contentsOf: events.filter { event in floor.map { event.id > $0 } ?? (event.at >= grant.createdAt) })
            }
        }
        fresh = fresh.filter { $0.author != me }.sorted { $0.id < $1.id }
        return (fresh, last?.at ?? notebook.visits.last { $0.author == me }?.at)
    }

    /// What a grant would be told by whats_new right now, without leaving a receipt.
    public static func pending(files: [(file: String, events: [Event])], notebook: Notebook, grant: Grant, calendar: Calendar) -> Report {
        let (events, since) = fresh(files: files, notebook: notebook, grant: grant)
        return report(events, all: files.flatMap(\.events), notebook: notebook, me: grant.author, since: since, calendar: calendar)
    }

    /// The owner's inbox, newest first. Everything other authors left that the owner might
    /// want to see: replies under the owner's lines and in conversations the owner is in,
    /// lines on other pages, labels and links placed on the owner's lines, names chosen.
    ///
    /// An item about a line is unread until the owner opens that line after it arrived: the
    /// opening is a visit in the owner's file naming the line. An item that is about no one
    /// line, labels folded together, a name, is unread until the owner next opens the inbox,
    /// whose visit records how long every event file was, so an event that reached this
    /// device late is still new.
    public static func items(files: [(file: String, events: [Event])], notebook: Notebook, calendar: Calendar) -> [InboxItem] {
        let owner = notebook.owner
        let looks = notebook.visits.filter { $0.author == owner && $0.read.what == .inbox }
        let seen = looks.last { $0.read.seen != nil }?.read.seen ?? [:]
        /// Per line, the latest opening by the owner.
        let opened: [ULID: ULID] = looks.reduce(into: [:]) { map, visit in
            guard let entry = visit.read.entry else { return }
            map[entry] = max(map[entry] ?? visit.id, visit.id)
        }
        func unread(_ event: Event, about entry: ULID) -> Bool {
            opened[entry].map { $0 < event.id } ?? true
        }

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
                // For what is about no one line: new until the inbox was next opened.
                let fresh = index >= floor
                switch event.payload {
                case .noteAdd(let p):
                    guard let entry = notebook.entry(p.entry), let note = entry.notes.first(where: { $0.id == p.note }) else { continue }
                    let mine = entry.notes.filter { $0.author == owner }
                    // Under the owner's line, or in a conversation the owner is part of.
                    guard entry.author == owner || !mine.isEmpty else { continue }
                    items.append(InboxItem(
                        id: event.id, author: event.author, at: event.at, kind: .reply, entry: entry.id,
                        what: "replied", text: note.text, about: entry.author == owner ? words(entry) : nil,
                        asks: asks(note.text), answered: mine.contains { $0.id > note.id }, unread: unread(event, about: entry.id)))

                case .entryCreate(let p):
                    guard let entry = notebook.entry(p.entry) else { continue }
                    items.append(InboxItem(
                        id: event.id, author: event.author, at: event.at, kind: .line, entry: entry.id,
                        what: entry.page == owner ? "added to your page" : "wrote", text: words(entry), about: nil,
                        asks: asks(entry.text), answered: entry.notes.contains { $0.author == owner }, unread: unread(event, about: entry.id)))

                case .labelAttach(let p):
                    // A label on the author's own line is their housekeeping, not news.
                    let label = p.label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    guard let entry = notebook.entry(p.entry), entry.author != event.author, entry.labels.contains(label) else { continue }
                    let key = LabelKey(author: event.author, label: label, day: DayKey(event.at, calendar: calendar))
                    var group = labels[key] ?? LabelGroup(last: event)
                    if event.id > group.last.id { group.last = event }
                    if !group.entries.contains(entry.id) { group.entries.append(entry.id) }
                    group.unread = group.unread || fresh
                    labels[key] = group

                case .linkAdd(let p):
                    // The older shape: a thread, and done when it closes.
                    guard let later = notebook.entry(p.later), let earlier = notebook.entry(p.earlier),
                          later.author != event.author || earlier.author != event.author,
                          later.carriesOn.contains(where: { $0.to == p.earlier }) else { continue }
                    items.append(InboxItem(
                        id: event.id, author: event.author, at: event.at, kind: .link, entry: later.id,
                        what: p.closes ? "marked done" : "joined", text: words(later),
                        about: (p.closes ? "done by this: " : "carries on from: ") + words(earlier),
                        asks: false, answered: false, unread: unread(event, about: later.id)))

                case .link(let p):
                    // A thread between lines. A citation in a note shows with the note itself.
                    guard let later = notebook.entry(p.from), let earlier = notebook.entry(p.to),
                          later.author != event.author || earlier.author != event.author,
                          later.carriesOn.contains(where: { $0.to == p.to }) else { continue }
                    items.append(InboxItem(
                        id: event.id, author: event.author, at: event.at, kind: .link, entry: later.id,
                        what: "joined", text: words(later), about: "carries on from: " + words(earlier),
                        asks: false, answered: false, unread: unread(event, about: later.id)))

                case .done(let p):
                    guard let entry = notebook.entry(p.entry), entry.author != event.author, entry.done?.id == event.id else { continue }
                    items.append(InboxItem(
                        id: event.id, author: event.author, at: event.at, kind: .link, entry: entry.id,
                        what: "marked done", text: words(entry),
                        about: p.by.flatMap { notebook.entry($0) }.map { "done by this: " + words($0) },
                        asks: false, answered: false, unread: unread(event, about: entry.id)))

                case .nameSet(let p):
                    let name = p.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty, notebook.name(of: event.author) == name else { continue }
                    items.append(InboxItem(
                        id: event.id, author: event.author, at: event.at, kind: .name, entry: nil,
                        what: "is called \(name) now", text: "", about: nil,
                        asks: false, answered: false, unread: fresh))

                case .entryEdit, .entryDelete, .mediaAttach, .noteEdit, .noteRemove, .labelDetach, .linkRemove, .unlink, .undone,
                     .visit, .grantCreate, .grantRevoke:
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
                asks: false, answered: false,
                unread: one.map { unread(group.last, about: $0) } ?? group.unread))
        }

        return items.sorted { $0.id > $1.id }
    }

    /// The receipt for the owner opening the inbox: how long every file was, so what is
    /// about no one line counts as seen from here, and how much was new.
    public static func look(files: [(file: String, events: [Event])], unread: Int) -> Payload.Visit {
        .init(what: .inbox, count: unread, seen: Dictionary(uniqueKeysWithValues: files.map { ($0.file, $0.events.count) }))
    }

    /// The receipt for the owner opening one line: everything in the inbox about it is read.
    public static func look(at entry: ULID) -> Payload.Visit {
        .init(what: .inbox, count: 1, entry: entry)
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
            case .unlink(let p):
                takenBack.append("\(who(event.author)) took back the link from \(p.from) to \(p.to)")
            case .undone(let p):
                takenBack.append("\(who(event.author)) took done back from \(p.entry)")
            case .labelAttach(let p):
                marks.append("\(who(event.author)) filed \(p.entry) under #\(p.label)")
            case .linkAdd(let p):
                marks.append("\(who(event.author)) linked \(p.later) back to \(p.earlier)\(p.closes ? ", closing it" : "")")
            case .link(let p):
                let kind = notebook.note(p.from) != nil ? "cited \(p.to) in a note" : "linked \(p.from) back to \(p.to)"
                marks.append("\(who(event.author)) \(kind)")
            case .done(let p):
                marks.append("\(who(event.author)) marked \(p.entry) done\(p.by.map { " by \($0)" } ?? "")")
            case .nameSet(let p):
                names.append("\(event.author) is called \(p.name) now")
            case .visit, .grantCreate, .grantRevoke:
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
