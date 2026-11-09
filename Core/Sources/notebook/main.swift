import Core
import Foundation

// The door, as a command. Any process with the folder can read it and append to its own file.
//
//   notebook init <folder> --owner <id>
//   notebook add <folder> "<text>" [--author <id>] [--device <id>] [--at <iso8601>]
//   notebook note <folder> <entry-id> "<text>" --author <id> [--device <id>]
//   notebook label <folder> <entry-id> <label> --author <id> [--remove]
//   notebook link <folder> <from-id> <to-id> --author <id> [--remove]
//   notebook done <folder> <entry-id> [--by <id>] --author <id> [--remove]
//   notebook name <folder> "<name>" --author <id>                  what that author is called from now on
//   notebook list <folder> [--label <label>] [--since YYYY-MM-DD]   one line per entry, with ids
//   notebook show <folder> [--label <label>]                        the fold, as day pages
//   notebook labels <folder>                                        every label and its count
//   notebook project <folder>                                       write days/*.md
//   notebook log <folder>                                           every event, one per line

struct Arguments {
    var positional: [String] = []
    var options: [String: String] = [:]
    var flags: Set<String> = []

    init(_ raw: [String]) {
        var index = 0
        while index < raw.count {
            let word = raw[index]
            if word.hasPrefix("--") {
                let name = String(word.dropFirst(2))
                if index + 1 < raw.count, !raw[index + 1].hasPrefix("--"), ["owner", "author", "device", "at", "label", "since"].contains(name) {
                    options[name] = raw[index + 1]
                    index += 2
                } else {
                    flags.insert(name)
                    index += 1
                }
            } else {
                positional.append(word)
                index += 1
            }
        }
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func folder(_ arguments: Arguments, at index: Int) -> URL {
    guard arguments.positional.count > index else { fail("missing folder") }
    return URL(fileURLWithPath: arguments.positional[index], isDirectory: true)
}

func calendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    calendar.locale = Locale(identifier: "en_GB")
    return calendar
}

func parseDate(_ text: String?) -> Date {
    guard let text else { return Date() }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: text) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    guard let date = formatter.date(from: text) else { fail("not an ISO 8601 date: \(text)") }
    return date
}

func parseDay(_ text: String) -> DayKey {
    let parts = text.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { fail("not a day: \(text), want YYYY-MM-DD") }
    return DayKey(year: parts[0], month: parts[1], day: parts[2])
}

let arguments = Arguments(Array(CommandLine.arguments.dropFirst()))
guard let command = arguments.positional.first else {
    fail("usage: notebook init|add|note|label|link|done|thing|fact|name|list|show|labels|project|log <folder> ...")
}

let generator = ULIDGenerator()
/// Anything written beside the owner's lines names its author. There is no default.
func author(_ arguments: Arguments) -> Author {
    guard let id = arguments.options["author"], !id.isEmpty else { fail("--author <id> is required") }
    return Author(rawValue: id)
}

let host = DeviceID(rawValue: arguments.options["device"] ?? (Host.current().localizedName ?? "cli").lowercased().replacingOccurrences(of: " ", with: "-"))

func time(_ date: Date) -> String {
    let parts = calendar().dateComponents([.hour, .minute], from: date)
    return String(format: "%02d:%02d", parts.hour!, parts.minute!)
}

do {
    switch command {
    case "init":
        guard let owner = arguments.options["owner"] else { fail("--owner <id> is required") }
        let store = try FileStore.create(at: folder(arguments, at: 1), owner: Author(rawValue: owner))
        print("notebook \(store.manifest.id) for \(owner) at \(store.root.path)")

    case "add":
        let store = try FileStore.open(folder(arguments, at: 1))
        guard arguments.positional.count > 2 else { fail("missing text") }
        let at = parseDate(arguments.options["at"])
        let author = Author(rawValue: arguments.options["author"] ?? store.manifest.owner.rawValue)
        let id = generator.next(at: at)
        try store.append(Event(
            id: id, author: author, device: host, at: at,
            payload: .entryCreate(.init(entry: id, text: arguments.positional[2], startedAt: at))
        ))
        print(id)

    case "note":
        let store = try FileStore.open(folder(arguments, at: 1))
        guard arguments.positional.count > 3, let entry = ULID(arguments.positional[2]) else { fail("usage: note <folder> <entry-id> <text>") }
        guard try store.load().entry(entry) != nil else { fail("no such entry: \(entry)") }
        let at = parseDate(arguments.options["at"])
        let author = author(arguments)
        let id = generator.next(at: at)
        try store.append(Event(
            id: id, author: author, device: host, at: at,
            payload: .noteAdd(.init(entry: entry, note: id, text: arguments.positional[3]))
        ))
        print(id)

    case "label":
        let store = try FileStore.open(folder(arguments, at: 1))
        guard arguments.positional.count > 3, let entry = ULID(arguments.positional[2]) else { fail("usage: label <folder> <entry-id> <label> [--remove]") }
        guard try store.load().entry(entry) != nil else { fail("no such entry: \(entry)") }
        let at = parseDate(arguments.options["at"])
        let author = author(arguments)
        let label = arguments.positional[3]
        let payload: Payload = arguments.flags.contains("remove")
            ? .labelDetach(.init(entry: entry, label: label))
            : .labelAttach(.init(entry: entry, label: label))
        try store.append(Event(id: generator.next(at: at), author: author, device: host, at: at, payload: payload))
        print("\(arguments.flags.contains("remove") ? "-" : "+")\(label.lowercased()) \(entry)")

    case "link":
        let store = try FileStore.open(folder(arguments, at: 1))
        guard arguments.positional.count > 3, let from = ULID(arguments.positional[2]), let to = ULID(arguments.positional[3]) else {
            fail("usage: link <folder> <from-id> <to-id> [--remove]    a later line to an earlier one, or a note to a line")
        }
        let notebook = try store.load()
        guard let target = notebook.entry(to) else { fail("no such line: \(to)") }
        if let later = notebook.entry(from) {
            guard (target.startedAt, target.id) < (later.startedAt, later.id) else { fail("\(to) is not earlier than \(from)") }
        } else if notebook.note(from) == nil {
            fail("no such line or note: \(from)")
        }
        let at = parseDate(arguments.options["at"])
        let author = author(arguments)
        let remove = arguments.flags.contains("remove")
        let payload: Payload = remove ? .unlink(.init(from: from, to: to)) : .link(.init(from: from, to: to))
        try store.append(Event(id: generator.next(at: at), author: author, device: host, at: at, payload: payload))
        print("\(remove ? "-" : "+")\(from) → \(to)")

    case "done":
        let store = try FileStore.open(folder(arguments, at: 1))
        guard arguments.positional.count > 2, let entry = ULID(arguments.positional[2]) else {
            fail("usage: done <folder> <entry-id> [--by <entry-id>] [--remove]")
        }
        let notebook = try store.load()
        guard notebook.entry(entry) != nil else { fail("no such line: \(entry)") }
        let by = arguments.options["by"].flatMap(ULID.init)
        if let by, notebook.entry(by) == nil { fail("no such line: \(by)") }
        let at = parseDate(arguments.options["at"])
        let author = author(arguments)
        let remove = arguments.flags.contains("remove")
        let payload: Payload = remove ? .undone(.init(entry: entry)) : .done(.init(entry: entry, by: by))
        try store.append(Event(id: generator.next(at: at), author: author, device: host, at: at, payload: payload))
        print("\(remove ? "-" : "+")done \(entry)\(by.map { " by \($0)" } ?? "")")

    case "thing":
        let store = try FileStore.open(folder(arguments, at: 1))
        guard arguments.positional.count > 2, !arguments.positional[2].trimmingCharacters(in: .whitespaces).isEmpty else {
            fail("usage: thing <folder> <name> [--kind <word>] --author <id>    a thing lines can belong to, through link")
        }
        let at = parseDate(arguments.options["at"])
        let author = author(arguments)
        let id = generator.next(at: at)
        try store.append(Event(id: id, author: author, device: host, at: at,
                               payload: .thingSet(.init(thing: id, name: arguments.positional[2], kind: arguments.options["kind"]))))
        print("+\(id) \(arguments.positional[2])")

    case "fact":
        let store = try FileStore.open(folder(arguments, at: 1))
        guard arguments.positional.count > 4, let on = ULID(arguments.positional[2]) else {
            fail("usage: fact <folder> <line-or-thing-id> <key> <value> [--unit <unit>] [--remove] --author <id>    a number with a unit, or words")
        }
        let notebook = try store.load()
        guard notebook.entry(on) != nil || notebook.thing(on) != nil else { fail("no such line or thing: \(on)") }
        let at = parseDate(arguments.options["at"])
        let author = author(arguments)
        let key = arguments.positional[3]
        let payload: Payload
        if arguments.flags.contains("remove") {
            payload = .factRemove(.init(on: on, key: key))
        } else if let number = Double(arguments.positional[4]) {
            payload = .factSet(.init(on: on, key: key, value: .number(number, unit: arguments.options["unit"])))
        } else {
            payload = .factSet(.init(on: on, key: key, value: .words(arguments.positional[4])))
        }
        try store.append(Event(id: generator.next(at: at), author: author, device: host, at: at, payload: payload))
        print("\(arguments.flags.contains("remove") ? "-" : "+")\(key.lowercased()) \(on)")

    case "name":
        let store = try FileStore.open(folder(arguments, at: 1))
        guard arguments.positional.count > 2, !arguments.positional[2].trimmingCharacters(in: .whitespaces).isEmpty else { fail("usage: name <folder> <name> --author <id>") }
        let at = parseDate(arguments.options["at"])
        let author = author(arguments)
        try store.append(Event(id: generator.next(at: at), author: author, device: host, at: at,
                               payload: .nameSet(.init(name: arguments.positional[2]))))
        print("\(author) is called \(arguments.positional[2])")

    case "list":
        let store = try FileStore.open(folder(arguments, at: 1))
        let notebook = try store.load()
        let days = arguments.options["label"].map { notebook.days(labelled: $0, calendar: calendar()) } ?? notebook.days(calendar: calendar())
        let since = arguments.options["since"].map(parseDay)
        for day in days where since.map({ day.key >= $0 }) ?? true {
            for entry in day.entries {
                var text = entry.text.replacingOccurrences(of: "\n", with: " ")
                if text.count > 90 { text = String(text.prefix(89)) + "…" }
                var tail: [String] = []
                if !entry.media.isEmpty { tail.append("[\(entry.media.count) media]") }
                if !entry.notes.isEmpty { tail.append("[\(entry.notes.count) notes]") }
                if !entry.carriesOn.isEmpty { tail.append("[continues \(entry.carriesOn.map(\.to.string).joined(separator: " "))]") }
                if let done = entry.done { tail.append(done.by.map { "[done by \($0)]" } ?? "[done]") }
                tail.append(contentsOf: entry.labels.map { "#\($0)" })
                print("\(entry.id)  \(day.key) \(time(entry.startedAt))  \(text)\(tail.isEmpty ? "" : "  " + tail.joined(separator: " "))")
            }
        }

    case "show":
        let store = try FileStore.open(folder(arguments, at: 1))
        let notebook = try store.load()
        let days = arguments.options["label"].map { notebook.days(labelled: $0, calendar: calendar()) } ?? notebook.days(calendar: calendar())
        for day in days {
            print(Projector.markdown(for: day, calendar: calendar()))
        }

    case "labels":
        let store = try FileStore.open(folder(arguments, at: 1))
        for (label, count) in try store.load().labelCounts.sorted(by: { $0.key < $1.key }) {
            print("\(label)  \(count)")
        }

    case "project":
        let store = try FileStore.open(folder(arguments, at: 1))
        let written = try Projector.write(try store.load(), to: store, calendar: calendar())
        for url in written { print(url.path) }

    case "log":
        let store = try FileStore.open(folder(arguments, at: 1))
        for event in try store.loadEvents() {
            print(try JSONLines.encode(event))
        }

    default:
        fail("unknown command: \(command)")
    }
} catch {
    fail("\(error)")
}
