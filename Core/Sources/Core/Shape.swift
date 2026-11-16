import Foundation

/// What a kind of thing is: a paper, a plant, a person. A kind is one word on a thing, and
/// the word alone does not say what a paper has: each would come out with whatever facts
/// its maker happened to write, under whatever names. A shape says what the things of a
/// kind have, in order, and what each is, so they are made alike and drawn alike: a thing's
/// page is its shape's facts in its shape's order, each drawn by what it is.
///
/// A shape is found by its kind's word, as a tag is by its own, so every thing already
/// called a paper is of the paper shape the moment one is said. Anyone through the door
/// says what a kind has; the newest word stands; the owner drops it.
public struct KindShape: Hashable, Codable, Sendable, Identifiable {
    /// The kind, lower-case: "paper".
    public var kind: String
    /// What a thing of this kind has, in the order its page shows them.
    public var has: [Part]

    public var id: String { kind }

    public init(kind: String, has: [Part]) {
        self.kind = kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.has = has
    }

    /// One fact the things of a kind have: its key, what it is, and a few words on it for
    /// whoever fills it in.
    public struct Part: Hashable, Codable, Sendable {
        public var key: String
        /// What it is, as a word; one this build does not know is drawn as plain words.
        public var `is`: String
        public var says: String?

        public init(_ key: String, _ what: What, _ says: String? = nil) {
            self.key = key
            self.is = what.rawValue
            self.says = says
        }

        public init(key: String, is what: String, says: String? = nil) {
            self.key = key
            self.is = what
            self.says = says
        }

        public var what: What { What(rawValue: `is`) ?? .words }
    }

    /// What a fact is, for how it is drawn: a few sentences as a paragraph, an address as a
    /// link, the rest as a row of the page.
    public enum What: String, Sendable, CaseIterable {
        case text, words, link, number, moment, span, place
    }

    /// The shapes most notebooks come to, there until someone says otherwise: what a paper,
    /// a book, a plant usually has. Said again through the door, a kind's shape is that.
    public static let usual: [String: KindShape] = Dictionary(uniqueKeysWithValues: [
        KindShape(kind: "paper", has: [Part("about", .text, "What it says and why it matters, in a few plain sentences."),
                                       Part("by", .words, "Who wrote it."), Part("when", .words, "The year, or the date."),
                                       Part("source", .link, "Where it is.")]),
        KindShape(kind: "article", has: [Part("about", .text, "What it says, in a few plain sentences."),
                                         Part("by", .words, "Who wrote it, or where it ran."), Part("when", .words, "The date."),
                                         Part("source", .link, "Where it is.")]),
        KindShape(kind: "talk", has: [Part("about", .text, "What it says, in a few plain sentences."),
                                      Part("by", .words, "Who gave it."), Part("when", .words, "The year, or the date."),
                                      Part("source", .link, "Where it can be watched or read.")]),
        KindShape(kind: "book", has: [Part("about", .text, "What it is about, in a few plain sentences."),
                                      Part("by", .words, "Who wrote it."), Part("state", .words, "Wished for, on the shelf, being read, read."),
                                      Part("source", .link, "Where it is, when it is somewhere.")]),
        KindShape(kind: "plant", has: [Part("species", .words, "What it is."), Part("state", .words, "How it stands now."),
                                       Part("planted", .moment, "When it went into soil."), Part("about", .text, "Anything worth knowing of it.")]),
        KindShape(kind: "person", has: [Part("about", .text, "Who they are to the owner, in a sentence or two.")]),
        KindShape(kind: "project", has: [Part("about", .text, "What it is for."), Part("state", .words, "Where it stands.")]),
        KindShape(kind: "streak", has: [Part("about", .text, "What is being kept up, in a sentence."),
                                        Part("since", .moment, "When it began."),
                                        Part("counts", .words, "without: every day counts unless a line says it broke. with: a day counts when a line is with it."),
                                        Part("span", .span, "How long it is meant to run, when it has an end."),
                                        Part("ended", .moment, "When it was stopped, if it was.")]),
    ].map { ($0.kind, $0) })
}

/// One fact of a thing as its page draws it: under which word, as what.
public struct DrawnFact: Hashable, Sendable, Identifiable {
    public let fact: Fact
    public let what: KindShape.What
    /// The few words the shape says of it, when it is one the shape names.
    public let says: String?

    public var id: Fact.ID { fact.id }
    public var key: String { fact.key }
}

extension Notebook {
    /// What a thing's page shows, in order: the facts its shape names, in the shape's order
    /// and drawn as the shape says; then any others, drawn by what they look like, an address
    /// as a link, a long passage as a paragraph. One fact per key: the newest, whoever put it.
    public func drawn(_ thing: Thing) -> [DrawnFact] {
        var newest: [String: Fact] = [:]
        var order: [String] = []
        for fact in thing.facts {
            if newest[fact.key] == nil { order.append(fact.key) }
            if newest[fact.key].map({ $0.at <= fact.at }) ?? true { newest[fact.key] = fact }
        }
        var out: [DrawnFact] = []
        var placed: Set<String> = []
        for part in thing.kind.flatMap({ shape(of: $0) })?.has ?? [] {
            guard let fact = newest[part.key], placed.insert(part.key).inserted else { continue }
            out.append(DrawnFact(fact: fact, what: part.what, says: part.says))
        }
        for key in order where !placed.contains(key) {
            guard let fact = newest[key] else { continue }
            out.append(DrawnFact(fact: fact, what: Self.looksLike(fact.value), says: nil))
        }
        return out
    }

    /// What a fact no shape names is drawn as, from the value itself.
    static func looksLike(_ value: FactValue) -> KindShape.What {
        switch value {
        case .number: return .number
        case .moment: return .moment
        case .span: return .span
        case .place: return .place
        case .unknown: return .words
        case .words(let words):
            if let url = URL(string: words), url.scheme == "http" || url.scheme == "https", url.host != nil, !words.contains(" ") { return .link }
            return words.count > 90 ? .text : .words
        }
    }
}
