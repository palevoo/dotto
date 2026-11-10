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
            // Never a prompt while writing: a fix is asked for only where the phone already allows it.
            if oldValue.begun == nil, draft.begun != nil { location.refresh() }
        }
    }
    private static let draftKey = "notebook.draft"

    private let generator = ULIDGenerator()
    private let location = LocationSpy()
    /// Whether a line may keep where it was written, as the phone has it now.
    private(set) var locationStatus: CLAuthorizationStatus
    let walks = Walks()
    /// Photos taken here kept in Photos too, once switched on in Setup.
    let photos = PhotoKeeper()
    private var watcher: FolderWatcher?
    private var cloudWatcher: CloudWatcher?
    /// Where photos and voice notes stand with iCloud. Nil when the folder is not in iCloud
    /// Drive, or until iCloud has spoken.
    private(set) var cloud: CloudState?
    /// What others left that may want you, newest first. A projection of the fold.
    private(set) var inbox: [InboxItem] = []
    /// How many of those arrived since you last looked, on any device.
    var unread: Int { inbox.filter(\.unread).count }
    /// Which of your lines someone else has taken in, and who first. The page says so on
    /// today's lines that have nothing under them from that someone.
    private(set) var taken: [ULID: Author] = [:]
    /// Lines in the event files that could not be read and were passed over.
    private(set) var unreadable = 0
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
        walks.resume { [weak self] walks in self?.add(walks) ?? false }
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
    /// Only Setup asks.
    func allowLocation() {
        location.ask()
    }

    /// The app came to the front: where the phone is now is found out, so the next line has
    /// it by the time Return is pressed. Nothing is asked of the person.
    func refreshPlace() {
        location.refresh()
    }

    /// Walks from Health, switched on from Setup. From then on each one is a line.
    func turnOnWalks() {
        Task { await walks.turnOn { [weak self] walks in self?.add(walks) ?? false } }
    }

    /// Health, as an originator of its own: its lines land on your page under its name, and
    /// you drop one with a hold. It is called Health from the first line it writes.
    static let health = Author(rawValue: "health")

    /// Each walk is a line on your page at the moment it began, in Health's name.
    private func add(_ walks: [Walks.Walk]) -> Bool {
        guard !walks.isEmpty else { return true }
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
        return record(events)
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
            let read = try store.loadFiles()
            let files = read.map { (file: $0.name, events: $0.events) }
            notebook = Notebook(owner: store.manifest.owner, events: files.flatMap(\.events))
            days = notebook.days(calendar: calendar)
            inbox = Core.Inbox.items(files: files, notebook: notebook, calendar: calendar)
            taken = Core.Inbox.taken(files: files, notebook: notebook)
            unreadable = read.reduce(0) { $0 + $1.unreadable.count }
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

    /// A photo the camera just made goes into Photos too, when Setup says so, as the camera
    /// made it and where the phone is.
    func keepInPhotos(_ data: Data) {
        photos.keep(data, at: Date(), location: location.place(at: Date()))
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

    /// Your reply under a line, yours or anyone's: a line that says what it was said under.
    /// `answering` is the reply it answers, when it was written under one; it is then said
    /// under that reply, in the same conversation.
    func reply(to entry: ULID, text: String, answering: ULID? = nil) {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty, notebook.entry(entry) != nil else { return }
        let under = answering.flatMap { notebook.note($0)?.entry.id == entry ? $0 : nil } ?? entry
        let now = Date()
        let id = generator.next(at: now)
        record([Event(id: id, author: store.manifest.owner, device: device, at: now,
                      payload: .entryCreate(.init(entry: id, text: words, startedAt: now, under: under)))])
    }

    /// A voice note lands in the live line the moment it ends: the audio is kept in the
    /// notebook and waits in the line, before any words are made from it, so a take is never
    /// only a temporary file. Returns where the audio is kept, to be listened to for its
    /// words, or nil if it could not be kept, in which case the recording is left where it was.
    func addVoice(fileURL: URL, duration: TimeInterval, startedAt: Date) -> (hash: String, url: URL)? {
        do {
            let data = try Data(contentsOf: fileURL)
            let hash = try store.storeMedia(data, fileExtension: "m4a")
            try? FileManager.default.removeItem(at: fileURL)
            draft.add(DraftMedia(hash: hash, mime: "audio/mp4", duration: duration, at: startedAt),
                      beginning: startedAt, now: Date(), calendar: calendar)
            return (hash, store.mediaURL(hash: hash, fileExtension: "m4a"))
        } catch {
            NSLog("voice failed: \(error)")
            return nil
        }
    }

    /// The words of a voice note, once they have been made. They join the live line if the
    /// note is still waiting there. If Return came first, they become the words of the line
    /// it was stored as, when that line has none. Otherwise the note was taken out, and the
    /// words go with it.
    func addWords(_ words: String, ofVoice hash: String) {
        let said = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !said.isEmpty else { return }
        if draft.media.contains(where: { $0.hash == hash }) {
            draft.append(said, now: Date())
        } else if let line = notebook.entries.last(where: { entry in
            entry.author == store.manifest.owner && entry.text.isEmpty && entry.media.contains { $0.hash == hash }
        }) {
            edit(line.id, text: said)
        }
    }

    /// Stores the live line as one entry. Returns its id, or nil if there was nothing to store.
    @discardableResult
    func commitDraft() -> ULID? {
        guard let stored = draft.stored(by: store.manifest.owner, on: device, here: draft.begun.flatMap { location.place(at: $0) }, ids: generator,
                                        now: Date(), calendar: calendar) else {
            draft = Draft()
            return nil
        }
        // Words that could not be written stay in the line.
        guard record(stored.events) else { return nil }
        draft = Draft()
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

    /// Your own word that a line is finished.
    func markDone(_ entry: ULID) {
        record(.done(.init(entry: entry)))
    }

    // MARK: - Loops

    /// A loop set: your event, which every device knows and the Mac runs. With an id, a loop
    /// set again, or a proposal taken under its own id.
    func setLoop(id: ULID? = nil, name: String, grant: ULID, wake: Loop.Wake, brief: String?, turns: Int = 40, budget: Double = 2) {
        let words = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        let said = brief?.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        let loop = id ?? generator.next(at: now)
        record([Event(id: generator.next(at: now), author: store.manifest.owner, device: device, at: now,
                      payload: .loopSet(.init(loop: loop, name: words, grant: grant, wake: wake.kind, at: wake.at,
                                              brief: said?.isEmpty == false ? said : nil, turns: turns, budget: budget)))])
    }

    /// A loop stopped; or a proposal declined, which is a stop of its id before any set.
    func stopLoop(_ id: ULID) {
        record(.loopStop(.init(loop: id)))
    }

    /// A proposal taken: the loop set under the proposal's id, as the proposer's grant.
    func takeProposal(_ proposal: LoopProposal) {
        guard let grant = proposal.grant, notebook.grants.contains(where: { $0.id == grant }) else { return }
        setLoop(id: proposal.id, name: proposal.name, grant: grant, wake: proposal.wake, brief: proposal.brief,
                turns: proposal.turns, budget: proposal.budget)
    }

    func declineProposal(_ proposal: LoopProposal) {
        stopLoop(proposal.id)
    }

    /// A fact taken off, whoever put it there: one hold.
    func removeFact(_ fact: Fact) {
        record(.factRemove(.init(on: fact.on, key: fact.key, of: fact.author)))
    }

    /// What a kind has, dropped: one hold. Its things keep their word and their facts.
    func removeShape(_ kind: String) {
        record(.shapeRemove(.init(kind: kind)))
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
        record(.entryEdit(.init(entry: note.id, text: words)))
    }

    /// A reply taken away: yours, or anyone's from under your line.
    func removeNote(_ note: Note) {
        record(.entryDelete(.init(entry: note.id)))
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

    /// False when the events could not be written to the folder; nothing is shown then.
    @discardableResult
    private func record(_ events: [Event]) -> Bool {
        do {
            try store.append(events)
        } catch {
            NSLog("append failed: \(error)")
            return false
        }
        for event in events { notebook.apply(event) }
        days = notebook.days(calendar: calendar)
        refreshInbox()
        projectSoon()
        return true
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
    private var last: (place: Location, at: Date)?
    /// How old a fix may be and still be where a line was written.
    private static let fresh: TimeInterval = 120

    /// Where the phone was at a moment: the last fix, if it was found out no earlier than
    /// two minutes before that moment. A line long in the writing keeps the place it began
    /// in. An older fix is where the phone was before, at home before the drive, and a line
    /// would rather keep no place than the wrong one.
    func place(at moment: Date) -> Location? {
        guard let last, last.at >= moment.addingTimeInterval(-Self.fresh) else { return nil }
        return last.place
    }
    var onChange: ((CLAuthorizationStatus) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var status: CLAuthorizationStatus { manager.authorizationStatus }

    /// From Setup: asks the phone for permission if it has not been asked, else for a fix.
    func ask() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        default: break
        }
    }

    /// A fix, where the phone already allows it. Never a prompt.
    func refresh() {
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways { manager.requestLocation() }
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
        last = (Location(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude, accuracy: fix.horizontalAccuracy), fix.timestamp)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
