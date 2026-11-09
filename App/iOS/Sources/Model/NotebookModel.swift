import Core
import CoreLocation
import Foundation
import Observation

/// The app's one piece of state: the folder, its fold, and the line being written.
@MainActor
@Observable
final class NotebookModel {
    let store: FileStore
    let device: DeviceID
    let calendar: Calendar

    private(set) var notebook: Notebook
    private(set) var days: [Day] = []

    /// The live line, as Core keeps its rules. Nothing stores it but Return; it is written
    /// down as it changes, so a switch away, a tap elsewhere or a relaunch finds the words
    /// still waiting. The phone's place is asked for the moment the line begins.
    private(set) var draft = Draft() {
        didSet {
            persistDraft()
            if oldValue.begun == nil, draft.begun != nil { location.ask() }
        }
    }
    private static let draftKey = "notebook.draft"

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
    /// What others left that may want you, newest first. A projection of the fold.
    private(set) var inbox: [InboxItem] = []
    /// How many of those arrived since you last looked, on any device.
    var unread: Int { inbox.filter(\.unread).count }
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
        restoreDraft()
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

    /// Health, as an originator of its own: its lines land on your page under its name, and
    /// you drop one with a hold. It is called Health from the first line it writes.
    static let health = Author(rawValue: "health")

    /// Each walk is a line on your page at the moment it began, in Health's name.
    private func add(_ walks: [Walks.Walk]) {
        guard !walks.isEmpty else { return }
        var events: [Event] = []
        if notebook.name(of: Self.health) == nil {
            events.append(Event(id: generator.next(at: Date()), author: Self.health, device: device, at: Date(),
                                payload: .nameSet(.init(name: "Health"))))
        }
        for walk in walks {
            let id = generator.next(at: walk.start)
            events.append(Event(id: id, author: Self.health, device: device, at: Date(),
                                payload: .entryCreate(.init(entry: id, text: Walks.sentence(for: walk, locale: calendar.locale ?? .current),
                                                            startedAt: walk.start, page: store.manifest.owner))))
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

    // MARK: - The live line, as the page sees it

    /// The words in the live line. The field writes them; the draft fixes its moment.
    var draftText: String {
        get { draft.text }
        set { draft.write(newValue, now: Date()) }
    }
    var draftMedia: [DraftMedia] { draft.media }
    var draftIsEmpty: Bool { draft.isEmpty }
    /// Whether the line is stored at its photos' moment. Tapping the time toggles it.
    var draftKeepsPhotoMoment: Bool { draft.keepsPhotoMoment }
    /// The moment the photos in the line offer, when they all come from one earlier day.
    var draftPhotoMoment: Date? { draft.photoMoment(now: Date(), calendar: calendar) }
    /// The moment the line will be stored at: the photos' own, if kept, else when it began.
    var draftMoment: Date? { draft.moment(now: Date(), calendar: calendar) }

    func toggleDraftMoment() { draft.toggleMoment(now: Date(), calendar: calendar) }

    // MARK: - Reading

    /// Re-folds the whole folder. Cheap for years of a notebook.
    func reload() {
        do {
            let files = try store.loadEventsByFile()
            notebook = Notebook(owner: store.manifest.owner, events: files.flatMap(\.events))
            days = notebook.days(calendar: calendar)
            inbox = Core.Inbox.items(files: files, notebook: notebook, calendar: calendar)
        } catch {
            NSLog("reload failed: \(error)")
        }
    }

    /// The inbox again, after something was written: a reply of yours answers an ask.
    private func refreshInbox() {
        guard let files = try? store.loadEventsByFile() else { return }
        inbox = Core.Inbox.items(files: files, notebook: notebook, calendar: calendar)
    }

    /// You opened the inbox. What is about no one line, labels folded together, a name, is
    /// read from here: the receipt records how long every event file was, so the same holds
    /// on every device. What is about a line stays until you open the line. Nothing is
    /// written when there was nothing of that kind new.
    func lookAtInbox() {
        guard inbox.contains(where: { $0.entry == nil && $0.unread }), let files = try? store.loadEventsByFile() else { return }
        record(.visit(Core.Inbox.look(files: files, unread: unread)))
    }

    /// You opened a line. Everything in the inbox about it is read, on every device.
    func lookAt(_ entry: ULID) {
        guard inbox.contains(where: { $0.entry == entry && $0.unread }) else { return }
        record(.visit(Core.Inbox.look(at: entry)))
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

    /// The live line, written down as it is: cheap, and the words survive anything short of Return.
    private func persistDraft() {
        let defaults = UserDefaults.standard
        if draft.isEmpty {
            defaults.removeObject(forKey: Self.draftKey)
            return
        }
        if let data = try? JSONEncoder().encode(draft) { defaults.set(data, forKey: Self.draftKey) }
    }

    /// Whatever was in the live line when the app last went away.
    private func restoreDraft() {
        guard let data = UserDefaults.standard.data(forKey: Self.draftKey),
              let kept = try? JSONDecoder().decode(Draft.self, from: data) else { return }
        draft = kept
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
            let now = Date()
            draft.add(DraftMedia(hash: hash, mime: "image/jpeg", width: photo.width, height: photo.height,
                                 at: at, location: location, fromBefore: fromBefore),
                      beginning: now, now: now, calendar: calendar)
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

    /// A passage read off a page lands in the live line as its words, in quotation marks,
    /// after whatever is there already.
    func addQuote(_ passage: String) {
        draft.append(passage, quoted: true, now: Date())
    }

    func removeDraftMedia(_ item: DraftMedia) {
        draft.remove(item.id, now: Date(), calendar: calendar)
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
            let now = Date()
            draft.add(DraftMedia(hash: hash, mime: "audio/mp4", duration: duration, at: startedAt),
                      beginning: startedAt, now: now, calendar: calendar)
            draft.append(transcript, now: now)
        } catch {
            NSLog("voice failed: \(error)")
        }
    }

    /// Stores the live line as one entry. Returns its id, or nil if there was nothing to store.
    @discardableResult
    func commitDraft() -> ULID? {
        defer { draft = Draft() }
        guard let stored = draft.stored(by: store.manifest.owner, on: device, here: location.last, ids: generator,
                                        now: Date(), calendar: calendar) else { return nil }
        record(stored.events)
        return stored.id
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
        record(.unlink(.init(from: link.from, to: link.to)))
    }

    /// Done taken back: the line is open again.
    func undone(_ entry: ULID) {
        record(.undone(.init(entry: entry)))
    }

    /// A fact taken off, whoever put it there: one hold.
    func removeFact(_ fact: Fact) {
        record(.factRemove(.init(on: fact.on, key: fact.key, of: fact.author)))
    }

    /// A thing dropped, with everything that belonged to it set loose: one hold.
    func removeThing(_ id: ULID) {
        record(.thingRemove(.init(thing: id)))
    }

    /// Your own link: this line carries on from an earlier one of yours.
    func link(_ later: ULID, from earlier: ULID) {
        guard let a = notebook.entry(earlier), let b = notebook.entry(later),
              (a.startedAt, a.id) < (b.startedAt, b.id) else { return }
        record(.link(.init(from: later, to: earlier)))
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
        refreshInbox()
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
