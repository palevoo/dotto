import Foundation

/// What happened in the notebook since one author last looked, said in a few lines so the
/// author knows where to go next. Replies first, since those are what it waits for; then
/// new lines, lines changed, things taken back, marks others left, names chosen.
public enum Inbox {
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
