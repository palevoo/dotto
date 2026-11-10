import AppKit
import Core
import Foundation
import Observation

/// The live line on the Mac: the same line the phone has, written here. Words typed, and
/// whatever lands from outside the keyboard, a paste, a drop on the dots in the menu bar or
/// on the line itself, a selection sent through Services. Nothing stores it but Return; it
/// is written down as it changes, so the words wait across a close or a relaunch.
///
/// The clipboard is read only when you paste, and a drop only when you drop it. Nothing is
/// watched.
@MainActor
@Observable
final class CaptureModel {
    let mac: MacModel

    private(set) var draft = Draft() {
        didSet { persist() }
    }
    /// Small pictures for what has landed, by hash.
    private(set) var thumbs: [String: NSImage] = [:]
    /// What could not land, in a sentence, until the next thing does.
    private(set) var note: String?
    /// Pictures still being made small enough to keep.
    private(set) var landing = 0

    private static let draftKey = "dotto.capture.draft"

    init(mac: MacModel) {
        self.mac = mac
        restore()
    }

    var hasNotebook: Bool { mac.store != nil }

    /// The words in the line. The field writes them; the draft fixes its moment.
    var text: String {
        get { draft.text }
        set { draft.write(newValue, now: Date()) }
    }

    /// Something arrives from outside the keyboard. Words and links join the words; pictures
    /// are kept in the notebook's media and wait in the line; anything else is named as left out.
    func take(_ offered: Offered) async {
        guard hasNotebook else {
            note = "Pick the notebook folder first."
            return
        }
        // Files are read off the main thread.
        let arrivals = await Task.detached(priority: .userInitiated) { offered.arrivals() }.value
        var left: [String] = []
        for arrival in arrivals {
            switch arrival {
            case .words(let words):
                draft.append(words, now: Date())
            case .picture(let data):
                landing += 1
                let picture = await Task.detached(priority: .userInitiated) { Core.Picture.process(data) }.value
                landing -= 1
                guard let picture, let hash = mac.keepPicture(picture) else {
                    left.append("a picture that could not be read")
                    continue
                }
                guard !draft.media.contains(where: { $0.hash == hash }) else { continue }
                thumbs[hash] = NSImage(data: picture.thumbnail)
                let now = Date()
                draft.add(DraftMedia(hash: hash, mime: "image/jpeg", width: picture.width, height: picture.height, at: now),
                          beginning: now, now: now, calendar: .current)
            case .leftOut(let name):
                left.append(name)
            }
        }
        note = left.isEmpty ? nil : "Left out: \(left.joined(separator: ", ")). Words, links and pictures land here for now."
    }

    func remove(_ item: DraftMedia) {
        draft.remove(item.id, now: Date(), calendar: .current)
        thumbs[item.hash] = nil
    }

    /// Return. The line is stored as one line of yours, from this Mac. False when there was
    /// nothing to store, or it could not be written, in which case the words stay.
    @discardableResult
    func commit() -> Bool {
        guard landing == 0, mac.keep(draft) != nil else { return false }
        draft = Draft()
        thumbs = [:]
        note = nil
        return true
    }

    private func persist() {
        let defaults = UserDefaults.standard
        if draft.isEmpty {
            defaults.removeObject(forKey: Self.draftKey)
        } else if let data = try? JSONEncoder().encode(draft) {
            defaults.set(data, forKey: Self.draftKey)
        }
    }

    /// Whatever was in the line when the app last went away, with its pictures read again
    /// from the notebook.
    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: Self.draftKey),
              let kept = try? JSONDecoder().decode(Draft.self, from: data) else { return }
        draft = kept
        for item in kept.media {
            guard let url = mac.mediaURL(hash: item.hash) else { continue }
            Task {
                let small = await Task.detached(priority: .utility) { Core.Picture.jpeg(contentsOf: url, maxSide: Core.Picture.thumbnailSide) }.value
                if let small { thumbs[item.hash] = NSImage(data: small) }
            }
        }
    }
}

/// Files that are promised rather than there: a screenshot's floating thumbnail, a photo
/// dragged out of Photos. The system writes them where it is told, and says when each is done.
@MainActor
enum Promised {
    /// The promises on a drag's pasteboard. Read during the drop, while the pasteboard is valid.
    static func receivers(on pasteboard: NSPasteboard) -> [NSFilePromiseReceiver] {
        (pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver]) ?? []
    }

    /// The promised files, written into a folder of their own under the temporary directory.
    /// The caller removes the folder once it has taken what it wants.
    static func receive(_ receivers: [NSFilePromiseReceiver]) async -> (files: [URL], folder: URL?) {
        guard !receivers.isEmpty else { return ([], nil) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("dotto-drop-\(UUID().uuidString)", isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil else { return ([], nil) }
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        var files: [URL] = []
        for receiver in receivers {
            // One call back per promised file. The names are known only once receiving has
            // begun; the types are known now, one per file.
            let expected = receiver.fileTypes.count
            guard expected > 0 else { continue }
            let arrived: [URL] = await withCheckedContinuation { continuation in
                // One operation at a time on the queue, so the box is touched by one thread.
                final class Box: @unchecked Sendable { var urls: [URL] = []; var seen = 0 }
                let box = Box()
                receiver.receivePromisedFiles(atDestination: folder, options: [:], operationQueue: queue) { url, error in
                    box.seen += 1
                    if error == nil { box.urls.append(url) }
                    if box.seen == expected { continuation.resume(returning: box.urls) }
                }
            }
            files += arrived
        }
        return (files, folder)
    }
}
