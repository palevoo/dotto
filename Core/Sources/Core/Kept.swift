import Foundation

/// What a line points at, opened and kept beside it. A line of the owner's with a link in it
/// points at a page, a paper; the home opens exactly that, and keeps its words in the
/// notebook's media like a photo, attached to the line with where it came from. Anyone who
/// reads the line then reads what it pointed at, as part of the capture, and nobody who
/// reads has to reach outside to do it.
///
/// It goes by the owner's word and nothing else: only links in the owner's own lines are
/// opened, never one in a line someone else wrote or in a page that was fetched, and never
/// an address on this machine or this network.
public enum Web {
    /// The links in some words: http and https addresses, without the full stop or bracket
    /// that ended the sentence they were in. Each once, in the order written.
    public static func links(in text: String) -> [URL] {
        var found: [URL] = []
        for piece in text.split(whereSeparator: { $0.isWhitespace || "<>\"«»“”".contains($0) }) {
            guard let start = piece.range(of: "http://") ?? piece.range(of: "https://") else { continue }
            var address = String(piece[start.lowerBound...])
            while let last = address.last, ".,;:!?)]}'’".contains(last) {
                // A bracket that closes one opened inside the address belongs to it.
                if last == ")", address.filter({ $0 == "(" }).count >= address.filter({ $0 == ")" }).count { break }
                address.removeLast()
            }
            guard let url = URL(string: address), url.host?.isEmpty == false, !found.contains(url) else { continue }
            found.append(url)
        }
        return found
    }

    /// Whether the home may open an address: out on the web, by name. Not this machine, not
    /// the network it is on, not a bare number that could be either; so a link in a line can
    /// never be a way to the door or to something at home.
    public static func mayOpen(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host?.lowercased(), !host.isEmpty, url.user == nil else { return false }
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") || host.hasSuffix(".internal") { return false }
        // A name, with a dot in it and a letter in its last part: not an address in numbers.
        guard host.contains("."), let last = host.split(separator: ".").last, last.contains(where: \.isLetter),
              !host.contains(":"), !host.hasPrefix("[") else { return false }
        return true
    }

    /// A page as the notebook keeps it: its title and its words.
    public struct Page: Equatable, Sendable {
        public var title: String?
        public var text: String

        public init(title: String?, text: String) {
            self.title = title
            self.text = text
        }

        /// The file kept in the notebook's media: the title, where it came from, the words.
        public func kept(from source: URL) -> String {
            var out = ""
            if let title, !title.isEmpty { out += "# \(title)\n\n" }
            out += "Kept from \(source.absoluteString)\n\n"
            return out + text + "\n"
        }
    }

    /// How much of a page is kept: enough for a long paper, not a whole site.
    public static let most = 300_000

    /// The words of a web page: what is between its tags, without its scripts, styles and
    /// furniture, one paragraph to a line. Plain enough to be read by anyone, exact enough
    /// to be quoted from.
    public static func page(fromHTML html: String) -> Page {
        var title: String?
        if let open = html.range(of: "<title", options: .caseInsensitive),
           let start = html[open.upperBound...].firstIndex(of: ">"),
           let close = html.range(of: "</title", options: .caseInsensitive, range: start..<html.endIndex) {
            let raw = unescaped(String(html[html.index(after: start)..<close.lowerBound]))
            title = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            if title?.isEmpty == true { title = nil }
        }
        var body = html
        for tag in ["script", "style", "noscript", "svg", "head", "nav", "footer", "form", "template", "iframe", "button", "aside"] {
            body = removing(tag, from: body)
        }
        var out = ""
        var inTag = false
        var tag = ""
        for character in body {
            if inTag {
                if character == ">" {
                    inTag = false
                    let name = tag.drop { $0 == "/" }.prefix { $0.isLetter || $0.isNumber }.lowercased()
                    if breaks.contains(name) { out.append("\n") }
                } else {
                    tag.append(character)
                }
            } else if character == "<" {
                inTag = true
                tag = ""
            } else {
                out.append(character)
            }
        }
        let lines = unescaped(out).split(separator: "\n").map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }.filter { !$0.isEmpty }
        return Page(title: title, text: String(lines.joined(separator: "\n").prefix(most)))
    }

    private static let breaks: Set<String> = ["p", "br", "div", "li", "tr", "h1", "h2", "h3", "h4", "h5", "h6", "section", "article",
                                               "blockquote", "pre", "table", "ul", "ol", "dd", "dt", "figcaption", "header", "main", "title"]

    /// Everything from each opening of a tag to its closing, gone.
    private static func removing(_ tag: String, from html: String) -> String {
        var out = ""
        var rest = html[...]
        while let open = rest.range(of: "<\(tag)", options: .caseInsensitive) {
            // "<head" must not take "<header": the name ends there.
            let after = rest[open.upperBound...].first
            guard after == nil || after == ">" || after == "/" || after?.isWhitespace == true else {
                out += rest[..<open.upperBound]
                rest = rest[open.upperBound...]
                continue
            }
            out += rest[..<open.lowerBound]
            guard let close = rest.range(of: "</\(tag)", options: .caseInsensitive, range: open.upperBound..<rest.endIndex),
                  let end = rest[close.upperBound...].firstIndex(of: ">") else {
                rest = rest[rest.endIndex...]
                break
            }
            rest = rest[rest.index(after: end)...]
        }
        return out + rest
    }

    private static let named: [String: String] = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "ndash": "–", "mdash": "—",
                                                   "hellip": "…", "rsquo": "’", "lsquo": "‘", "rdquo": "”", "ldquo": "“", "times": "×", "copy": "©"]

    /// The characters that pages write as &amp; and &#8217;, as themselves.
    static func unescaped(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = ""
        var rest = text[...]
        while let amp = rest.firstIndex(of: "&") {
            out += rest[..<amp]
            let tail = rest[rest.index(after: amp)...]
            guard let semi = tail.prefix(12).firstIndex(of: ";") else {
                out.append("&")
                rest = tail
                continue
            }
            let name = String(tail[..<semi])
            var character: String?
            if name.hasPrefix("#x") || name.hasPrefix("#X") {
                character = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else if name.hasPrefix("#") {
                character = UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else {
                character = named[name]
            }
            if let character {
                out += character
                rest = tail[tail.index(after: semi)...]
            } else {
                out.append("&")
                rest = tail
            }
        }
        return out + rest
    }
}

extension Notebook {
    /// What the owner's lines point at that nothing has been kept for yet: each link in a
    /// line the owner wrote on their own page since `since`, that the home may open and that
    /// no page kept beside the line came from. Lines by anyone else are never opened from.
    public func unopened(since: Date) -> [(entry: ULID, url: URL)] {
        entries.filter { $0.author == owner && $0.startedAt >= since }.flatMap { entry -> [(entry: ULID, url: URL)] in
            let kept = Set(entry.media.compactMap(\.source))
            return Web.links(in: entry.text).filter { Web.mayOpen($0) && !kept.contains($0.absoluteString) }.map { (entry.id, $0) }
        }
    }
}
