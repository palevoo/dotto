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
    /// When it happened: the shutter, or the start of the recording.
    let at: Date
    /// Where, if the photo knows.
    var location: Location?
    /// True for a photo brought in from the library rather than made here.
    var fromBefore = false

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
    /// Photos from before bring their own moment. The line can take it or keep now.
    var draftKeepsPhotoMoment = false

    private let generator = ULIDGenerator()
    private let location = LocationSpy()
    /// Whether a line may keep where it was written, as the phone has it now.
    private(set) var locationStatus: CLAuthorizationStatus
    let walks = Walks()
    private var watcher: FolderWatcher?
    private var cloudWatcher: CloudWatcher?
    /// Where photos and voice notes stand with iCloud. Nil when the folder is not in iCloud
    /// Drive, or until iCloud has spoken.
    private(set) var cloud: CloudState?
    private var reloadTask: Task<Void, Never>?
    private var projectTask: Task<Void, Never>?

    init(store: FileStore, device: DeviceID) {
        self.store = store
        self.device = device
        var calendar = Calendar.autoupdatingCurrent
        calendar.locale = Locale.autoupdatingCurrent
        self.calendar = calendar
        self.notebook = Notebook(owner: store.manifest.owner)
        locationStatus = location.status
        location.onChange = { [weak self] status in self?.locationStatus = status }
        reload()
        takeInbox()
        Pushes.shared.onToken = { [weak self] token in self?.savePushAddress(token) }
        if let token = Pushes.shared.token { savePushAddress(token) }
        watcher = FolderWatcher(directory: store.eventsDirectory) { [weak self] in
            self?.reloadSoon()
        }
        cloudWatcher = CloudWatcher(store: store) { [weak self] in
            guard let self else { return }
            cloud = cloudWatcher?.state
            reloadSoon()
        }
        walks.resume { [weak self] walks in self?.add(walks) }
    }

    /// Where this phone can be reached, kept in the folder for whoever holds it and the key.
    /// A build run from Xcode is on Apple's development side; TestFlight and the store are not.
    private func savePushAddress(_ token: String) {
        #if DEBUG
        let environment = "development"
        #else
        let environment = "production"
        #endif
        do {
            try store.savePushAddress(PushAddress(device: device, token: token, environment: environment,
                                                 topic: Bundle.main.bundleIdentifier ?? "", updatedAt: Date()))
        } catch {
            NSLog("push address failed: \(error)")
        }
    }

    /// Asks the phone, once, whether lines may keep their place. Refused, the answer lives in Settings.
    func allowLocation() {
        location.ask()
    }

    /// Walks from Health, switched on from Setup. From then on each one is a line.
    func turnOnWalks() {
        Task { await walks.turnOn { [weak self] walks in self?.add(walks) } }
    }

    /// Each walk is a line at the moment it began, in your ink: it is your walk.
    private func add(_ walks: [Walks.Walk]) {
        let events = walks.map { walk in
            let id = generator.next(at: walk.start)
            return Event(id: id, author: store.manifest.owner, device: device, at: Date(),
                         payload: .entryCreate(.init(entry: id, text: Walks.sentence(for: walk, locale: calendar.locale ?? .current),
                                                     startedAt: walk.start)))
        }
        record(events)
    }

    /// Lines kept from the share sheet while the app was away go into the notebook now.
    func takeInbox() {
        do {
            let events = try Inbox.take(into: store)
            guard !events.isEmpty else { return }
            for event in events { notebook.apply(event) }
            days = notebook.days(calendar: calendar)
            projectSoon()
        } catch {
            NSLog("inbox failed: \(error)")
        }
    }

    var today: DayKey { DayKey(Date(), calendar: calendar) }

    var draftIsEmpty: Bool { draftText.isEmpty && draftMedia.isEmpty }

    /// The moment the photos in the live line were taken, when they all come from one earlier
    /// day. The earliest of them. Nil when nothing in the line is from before, or when the photos
    /// are from different days.
    var draftPhotoMoment: Date? {
        let earlier = draftMedia.filter(\.fromBefore).map(\.at)
        guard !earlier.isEmpty, let first = earlier.min() else { return nil }
        let day = DayKey(first, calendar: calendar)
        guard day != today, earlier.allSatisfy({ DayKey($0, calendar: calendar) == day }) else { return nil }
        return first
    }

    /// The moment the line will be stored at: the photos' own, if chosen, else when writing began.
    var draftMoment: Date? {
        if draftKeepsPhotoMoment, let moment = draftPhotoMoment { return moment }
        return draftStartedAt
    }

    // MARK: - Reading

    /// Re-folds the whole folder. Cheap for years of a notebook.
    func reload() {
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

    /// A photo lands in the live line. From the camera it is of this moment; from the library it
    /// brings its own moment and place. Heavy work happens off the main thread.
    func addPhoto(_ data: Data, takenAt: Date? = nil, location: Location? = nil) async {
        let fromBefore = takenAt != nil
        let at = takenAt ?? Date()
        guard let photo = await Photo.process(data) else {
            NSLog("photo failed: could not read the image")
            return
        }
        do {
            let hash = try store.storeMedia(photo.jpeg, fileExtension: "jpg")
            Thumbs.save(photo.thumbnail, hash: hash)
            let hadMoment = draftPhotoMoment != nil
            draftMedia.append(DraftMedia(hash: hash, mime: "image/jpeg", width: photo.width, height: photo.height,
                                         duration: nil, at: at, location: location, fromBefore: fromBefore))
            touchDraft()
            // The first photo from before offers its moment; the line takes it until told otherwise.
            if !hadMoment, draftPhotoMoment != nil { draftKeepsPhotoMoment = true }
        } catch {
            NSLog("photo failed: \(error)")
        }
    }

    /// A photo from the library, with what it knows about itself: the original file through
    /// PhotoKit when the library allows, else the picker's copy and whatever is left in it.
    func importPhoto(_ data: Data, takenAt: Date?, location: Location?) async {
        var takenAt = takenAt
        var location = location
        if takenAt == nil || location == nil {
            let metadata = await Photo.metadata(of: data)
            takenAt = takenAt ?? metadata.takenAt
            location = location ?? metadata.location
        }
        await addPhoto(data, takenAt: takenAt, location: location)
    }

    func removeDraftMedia(_ item: DraftMedia) {
        draftMedia.removeAll { $0.id == item.id }
        touchDraft()
        if draftPhotoMoment == nil { draftKeepsPhotoMoment = false }
    }

    /// Your reply under a line, yours or anyone's.
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
        guard let startedAt = draftMoment, !text.isEmpty || !media.isEmpty else {
            draftText = ""
            draftMedia = []
            draftKeepsPhotoMoment = false
            return nil
        }
        let fromBefore = draftKeepsPhotoMoment && draftPhotoMoment != nil
        let place = fromBefore ? media.first(where: { $0.fromBefore && $0.location != nil })?.location : location.last
        let id = generator.next(at: startedAt)
        let now = Date()
        var events = [
            Event(id: id, author: store.manifest.owner, device: device, at: now,
                  payload: .entryCreate(.init(entry: id, text: text, startedAt: startedAt, location: place))),
        ]
        for item in media {
            events.append(Event(
                id: generator.next(at: now), author: store.manifest.owner, device: device, at: now,
                payload: .mediaAttach(.init(entry: id, hash: item.hash, mime: item.mime, width: item.width, height: item.height, duration: item.duration))
            ))
        }
        record(events)
        draftText = ""
        draftMedia = []
        draftStartedAt = nil
        draftKeepsPhotoMoment = false
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

    /// What you are called, to anyone else who reads: in the day files, on the Mac, through
    /// the door. To yourself you stay "you".
    func chooseName(_ name: String) {
        let chosen = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !chosen.isEmpty, chosen != notebook.name(of: store.manifest.owner) else { return }
        record(.nameSet(.init(name: chosen)))
    }

    /// A link taken back. Your words on either line are untouched.
    func unlink(_ link: Core.Link) {
        record(.linkRemove(.init(later: link.later, earlier: link.earlier)))
    }

    /// Your own link: this line carries on from an earlier one of yours.
    func link(_ later: ULID, from earlier: ULID) {
        guard let a = notebook.entry(earlier), let b = notebook.entry(later),
              (a.startedAt, a.id) < (b.startedAt, b.id) else { return }
        record(.linkAdd(.init(later: later, earlier: earlier)))
    }

    /// Your reply, changed. Only your own.
    func editNote(_ note: Note, text: String) {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard note.author == store.manifest.owner, !words.isEmpty, words != note.text else { return }
        record(.noteEdit(.init(note: note.id, text: words)))
    }

    /// A reply taken away: yours, or anyone's from under your line.
    func removeNote(_ note: Note) {
        record(.noteRemove(.init(note: note.id)))
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

/// Coordinates, captured once with permission, named later through the door. Never a prompt while writing.
final class LocationSpy: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var last: Location?
    var onChange: ((CLAuthorizationStatus) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var status: CLAuthorizationStatus { manager.authorizationStatus }

    func ask() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        default: break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
        }
        Task { @MainActor in self.onChange?(status) }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last else { return }
        last = Location(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude, accuracy: fix.horizontalAccuracy)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
