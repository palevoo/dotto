import Core
import CoreLocation
import Foundation
import Observation

/// Something that landed in the live line before it was stored.
struct DraftMedia: Identifiable, Hashable {
    let hash: String
    let mime: String
    let width: Int?
    let height: Int?
    let duration: Double?
    let at: Date

    var id: String { hash }
}

/// The app's one piece of state: the folder, its fold, and the line being written.
@MainActor
@Observable
final class NotebookModel {
    let store: FileStore
    let device: DeviceID
    let calendar: Calendar

    private(set) var notebook: Notebook
    private(set) var days: [Day] = []

    /// The live line. Its time is fixed the moment the first character or the first photo lands.
    var draftText = "" {
        didSet { touchDraft() }
    }
    private(set) var draftMedia: [DraftMedia] = []
    private(set) var draftStartedAt: Date?

    private let generator = ULIDGenerator()
    private let location = LocationSpy()
    private var watcher: FolderWatcher?
    private var reloadTask: Task<Void, Never>?
    private var projectTask: Task<Void, Never>?

    init(store: FileStore, device: DeviceID) {
        self.store = store
        self.device = device
        var calendar = Calendar.autoupdatingCurrent
        calendar.locale = Locale.autoupdatingCurrent
        self.calendar = calendar
        self.notebook = Notebook(owner: store.manifest.owner)
        reload()
        watcher = FolderWatcher(directory: store.eventsDirectory) { [weak self] in
            self?.reloadSoon()
        }
    }

    var today: DayKey { DayKey(Date(), calendar: calendar) }

    var draftIsEmpty: Bool { draftText.isEmpty && draftMedia.isEmpty }

    // MARK: - Reading

    /// Re-folds the whole folder. Cheap for years of a notebook.
    func reload() {
        downloadPlaceholders()
        do {
            notebook = try store.load()
            days = notebook.days(calendar: calendar)
        } catch {
            NSLog("reload failed: \(error)")
        }
    }

    private func reloadSoon() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }

    /// Files iCloud has not pulled down yet show as `.name.icloud`. Ask for them.
    private func downloadPlaceholders() {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: store.eventsDirectory.path) else { return }
        for name in names where name.hasSuffix(".icloud") {
            try? FileManager.default.startDownloadingUbiquitousItem(at: store.eventsDirectory.appendingPathComponent(name))
        }
    }

    // MARK: - The live line

    private func touchDraft(at date: Date = Date()) {
        if draftStartedAt == nil, !draftIsEmpty {
            draftStartedAt = date
            location.ask()
        }
        if draftIsEmpty {
            draftStartedAt = nil
        }
    }

    /// A photo lands in the live line. Heavy work happens off the main thread.
    func addPhoto(_ data: Data) async {
        let takenAt = Date()
        guard let photo = await Photo.process(data) else {
            NSLog("photo failed: could not read the image")
            return
        }
        do {
            let hash = try store.storeMedia(photo.jpeg, fileExtension: "jpg")
            Thumbs.save(photo.thumbnail, hash: hash)
            draftMedia.append(DraftMedia(hash: hash, mime: "image/jpeg", width: photo.width, height: photo.height, duration: nil, at: takenAt))
            touchDraft(at: takenAt)
        } catch {
            NSLog("photo failed: \(error)")
        }
    }

    /// A photo from the library keeps its own moment and place: it becomes a line on the day it
    /// was taken, and its id comes back so the page can go there. Without a date it lands in
    /// the live line like a fresh one.
    @discardableResult
    func importPhoto(_ data: Data) async -> ULID? {
        let metadata = await Photo.metadata(of: data)
        guard let takenAt = metadata.takenAt else {
            await addPhoto(data)
            return nil
        }
        guard let photo = await Photo.process(data) else {
            NSLog("import failed: could not read the image")
            return nil
        }
        do {
            let hash = try store.storeMedia(photo.jpeg, fileExtension: "jpg")
            Thumbs.save(photo.thumbnail, hash: hash)
            let id = generator.next(at: takenAt)
            let now = Date()
            record([
                Event(id: id, author: store.manifest.owner, device: device, at: takenAt,
                      payload: .entryCreate(.init(entry: id, text: "", startedAt: takenAt, location: metadata.location))),
                Event(id: generator.next(at: now), author: store.manifest.owner, device: device, at: now,
                      payload: .mediaAttach(.init(entry: id, hash: hash, mime: "image/jpeg", width: photo.width, height: photo.height))),
            ])
            return id
        } catch {
            NSLog("import failed: \(error)")
            return nil
        }
    }

    /// Your answer under a reader's note, in your own ink.
    func reply(to entry: ULID, text: String) {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty, notebook.entry(entry) != nil else { return }
        let now = Date()
        let id = generator.next(at: now)
        record([Event(id: id, author: store.manifest.owner, device: device, at: now,
                      payload: .noteAdd(.init(entry: entry, note: id, text: words)))])
    }

    /// A voice note lands in the live line: its words as text you can fix, the audio behind them.
    func addVoice(fileURL: URL, duration: TimeInterval, transcript: String, startedAt: Date) {
        do {
            let data = try Data(contentsOf: fileURL)
            let hash = try store.storeMedia(data, fileExtension: "m4a")
            try? FileManager.default.removeItem(at: fileURL)
            draftMedia.append(DraftMedia(hash: hash, mime: "audio/mp4", width: nil, height: nil, duration: duration, at: startedAt))
            touchDraft(at: startedAt)
            let words = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !words.isEmpty {
                draftText = draftText.isEmpty ? words : draftText + " " + words
            }
        } catch {
            NSLog("voice failed: \(error)")
        }
    }

    /// Stores the live line as one entry. Returns its id, or nil if there was nothing to store.
    @discardableResult
    func commitDraft() -> ULID? {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        let media = draftMedia
        guard let startedAt = draftStartedAt, !text.isEmpty || !media.isEmpty else {
            draftText = ""
            draftMedia = []
            return nil
        }
        let id = generator.next(at: startedAt)
        var events = [
            Event(id: id, author: store.manifest.owner, device: device, at: startedAt,
                  payload: .entryCreate(.init(entry: id, text: text, startedAt: startedAt, location: location.last))),
        ]
        for item in media {
            events.append(Event(
                id: generator.next(at: item.at), author: store.manifest.owner, device: device, at: item.at,
                payload: .mediaAttach(.init(entry: id, hash: item.hash, mime: item.mime, width: item.width, height: item.height, duration: item.duration))
            ))
        }
        record(events)
        draftText = ""
        draftMedia = []
        draftStartedAt = nil
        return id
    }

    // MARK: - Stored lines

    func edit(_ entry: ULID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let current = notebook.entry(entry), current.text != trimmed else { return }
        if trimmed.isEmpty, current.media.isEmpty {
            record(.entryDelete(.init(entry: entry)))
        } else {
            record(.entryEdit(.init(entry: entry, text: trimmed)))
        }
    }

    func delete(_ entry: ULID) {
        record(.entryDelete(.init(entry: entry)))
    }

    func mediaURL(_ media: Media) -> URL {
        store.mediaURL(hash: media.hash, fileExtension: Projector.fileExtension(forMIME: media.mime))
    }

    func mediaURL(_ media: DraftMedia) -> URL {
        store.mediaURL(hash: media.hash, fileExtension: Projector.fileExtension(forMIME: media.mime))
    }

    private func record(_ payload: Payload, at: Date = Date()) {
        record([Event(id: generator.next(at: at), author: store.manifest.owner, device: device, at: at, payload: payload)])
    }

    private func record(_ events: [Event]) {
        do {
            try store.append(events)
        } catch {
            NSLog("append failed: \(error)")
            return
        }
        for event in events { notebook.apply(event) }
        days = notebook.days(calendar: calendar)
        projectSoon()
    }

    /// Keeps `days/*.md` current a moment after the last change.
    private func projectSoon() {
        projectTask?.cancel()
        projectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            do {
                try Projector.write(notebook, to: store, calendar: calendar)
            } catch {
                NSLog("projection failed: \(error)")
            }
        }
    }
}

/// Watches the events folder and every file in it, so a line appended from another
/// device or by weeju shows up without the app being told.
final class FolderWatcher {
    private let directory: URL
    private let onChange: () -> Void
    private var sources: [DispatchSourceFileSystemObject] = []

    init(directory: URL, onChange: @escaping () -> Void) {
        self.directory = directory
        self.onChange = onChange
        rebuild()
    }

    deinit {
        sources.forEach { $0.cancel() }
    }

    private func rebuild() {
        sources.forEach { $0.cancel() }
        sources = []
        watch(directory, mask: [.write, .rename, .delete]) { [weak self] in
            self?.rebuild()
            self?.onChange()
        }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name.hasSuffix(".jsonl") {
            watch(directory.appendingPathComponent(name), mask: [.write, .extend, .rename, .delete]) { [weak self] in
                self?.onChange()
            }
        }
    }

    private func watch(_ url: URL, mask: DispatchSource.FileSystemEvent, handler: @escaping () -> Void) {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: mask, queue: .main)
        source.setEventHandler(handler: handler)
        source.setCancelHandler { close(descriptor) }
        source.resume()
        sources.append(source)
    }
}

/// Coordinates, captured once with permission, named later by a reader. Never a prompt while writing.
final class LocationSpy: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var last: Location?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func ask() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        default: break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last else { return }
        last = Location(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude, accuracy: fix.horizontalAccuracy)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
