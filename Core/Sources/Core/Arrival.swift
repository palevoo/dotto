import Foundation
import UniformTypeIdentifiers

/// What a drop, a paste or a service holds, as the system hands it over: files, a picture's
/// bytes, a link, words. Often several at once for one thing: a link dragged from a browser
/// is a link and its address as words; a picture copied from a page is the picture and the
/// address it came from.
public struct Offered: Equatable, Sendable {
    public var files: [URL]
    public var picture: Data?
    public var link: URL?
    public var words: String?

    public init(files: [URL] = [], picture: Data? = nil, link: URL? = nil, words: String? = nil) {
        self.files = files
        self.picture = picture
        self.link = link
        self.words = words
    }

    public var isEmpty: Bool { files.isEmpty && picture == nil && link == nil && (words ?? "").isEmpty }
}

/// What lands in the live line from outside the keyboard.
public enum Arrival: Equatable, Sendable {
    /// Words, or a link as its address. They join the words already in the line.
    case words(String)
    /// A picture's bytes, whatever the format.
    case picture(Data)
    /// A file the line cannot hold yet, by name, so the page can say so.
    case leftOut(String)
}

extension Offered {
    /// One thing offered is one thing landing, the most particular form of it: files before a
    /// loose picture, a picture before the link it came from, a link before the same address as
    /// words. Words that say more than an address win over a picture beside them: cells or a
    /// passage copied from an app that also hands over a rendering of them are words. Of files,
    /// pictures land and the rest are named as left out. `read` gives a file's bytes, nil when
    /// it cannot be read.
    public func arrivals(read: (URL) -> Data? = { try? Data(contentsOf: $0) }) -> [Arrival] {
        if !files.isEmpty {
            return files.map { file in
                let type = UTType(filenameExtension: file.pathExtension)
                if type?.conforms(to: .image) == true, let data = read(file) { return .picture(data) }
                return .leftOut(file.lastPathComponent)
            }
        }
        let said = (words ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let picture, said.isEmpty || said == link?.absoluteString { return [.picture(picture)] }
        if let link, said.isEmpty || said == link.absoluteString { return [.words(link.absoluteString)] }
        return said.isEmpty ? [] : [.words(said)]
    }
}

#if canImport(AppKit)
import AppKit

extension Offered {
    /// Every form a drop, a paste or a service may come in, on the Mac.
    @MainActor public static let pasteboardTypes: [NSPasteboard.PasteboardType] =
        [.fileURL, .URL, .png, .tiff, .string] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }

    /// What a pasteboard holds, read once, at the moment something was pasted or dropped.
    /// A loose picture is looked for only when no file is offered: a file copied in Finder
    /// rides with its icon, which is not the thing.
    @MainActor
    public static func read(_ pasteboard: NSPasteboard) -> Offered {
        let files = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        let links = (pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]) ?? []
        let picture = files.isEmpty ? (pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff)) : nil
        return Offered(files: files, picture: picture, link: links.first { !$0.isFileURL }, words: pasteboard.string(forType: .string))
    }
}
#endif
