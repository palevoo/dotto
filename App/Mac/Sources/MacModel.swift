import AppKit
import Core
import Foundation
import Observation

/// The Mac's state: which folder, which grants, whether the door is open, and the reader.
///
/// The app reads the folder the person picked in the open panel, remembered through a
/// bookmark, and nothing else on the disk. That is a promise the code keeps rather than one
/// macOS enforces: the app runs without the sandbox so that it can run the claude command
/// for the reader, which a sandboxed app may not.
///
/// Grants are the owner's events in the notebook, written from here into the owner's own
/// file for this Mac. The notebook keeps each key's hash; the keys themselves stay in this
/// Mac's keychain, so the Copy button works and nothing else needs them.
@MainActor
@Observable
final class MacModel {
    static var defaultPort: UInt16 { Identity.port }

    private(set) var folderURL: URL?
    private(set) var store: FileStore?
    private(set) var summary = ""
    /// The fold as last read, for the log and the words of the lines it names.
    private(set) var notebook: Notebook?
    /// What others left that may want the owner, newest first. The Mac shows it; the look
    /// that settles unread is the owner's, made on the phone.
    private(set) var inbox: [InboxItem] = []
    /// The grants that open the door, from the fold, with the keys this Mac holds filled in.
    private(set) var grants: [Grant] = []
    /// The door: shut until the server is up, open on a port, or failed with the reason.
    enum Door: Equatable {
        case closed
        case open(UInt16)
        case failed(String)
    }
    private(set) var door: Door = .closed
    /// The port the door is on, when it is open.
    var port: UInt16? {
        if case .open(let port) = door { return port }
        return nil
    }
    private(set) var problem: String?
    /// Said when the keychain would not let this app read a key it keeps there. The keys are
    /// still there, so nothing is offered that would replace them.
    private(set) var keysRefused: String?
    /// The push key on this Mac, if one has been chosen.
    private(set) var pushKey: PushKey?
    /// The phones the folder says can be reached.
    private(set) var pushAddresses: [PushAddress] = []
    /// What happened to the last push, in a sentence.
    private(set) var pushReport: String?
    /// The loops the notebook says run, each running here, by loop id.
    private(set) var runners: [ULID: ReaderRunner] = [:]
    /// The model the reader runs, empty for Claude Code's default.
    var readerModel = "" {
        didSet {
            UserDefaults.standard.set(readerModel, forKey: Identity.Kept.readerModel)
            for runner in runners.values { runner.model = readerModel }
        }
    }
    /// Bumped whenever the reader's status or a run changes, so the window redraws.
    private(set) var readerTick = 0

    private let bookmarkKey = Identity.Kept.folder
    private let ownerKey = Identity.Kept.owner
    private let deviceKey = Identity.Kept.device
    private let shared = DoorState()
    private let pusher = Pusher()
    private let generator = ULIDGenerator()
    private var server: DoorServer?
    private var watcher: FolderWatcher?
    private var cloud: CloudWatcher?
    private var summaryTask: Task<Void, Never>?

    init() {
        // What the app kept under its earlier id comes over before anything is read.
        if Identity.carriesOver { CarryOver.run() }
        pushKey = PushKeyStore.load()
        readerModel = UserDefaults.standard.string(forKey: Identity.Kept.readerModel) ?? ""
        restoreFolder()
        Task {
            await pusher.use(pushKey)
            await openDoor()
        }
    }

    // MARK: - The folder

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use This Folder"
        panel.message = "Pick the folder that holds your notebook, or an empty one to start it here."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        adopt(url, remember: true)
    }

    private func restoreFolder() {
        // dotto dev, told its folder on the command line: used for this launch, not remembered.
        if let named = Identity.folderArgument {
            adopt(named, remember: false)
            return
        }
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        var stale = false
        // A bookmark made while the app was sandboxed carries a security scope; it still resolves.
        guard let url = (try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale))
            ?? (try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)) else {
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
            return
        }
        adopt(url, remember: stale)
    }

    private func adopt(_ url: URL, remember: Bool) {
        do {
            let manifest = url.appendingPathComponent(FileStore.manifestName)
            let store = FileManager.default.fileExists(atPath: manifest.path)
                ? try FileStore.open(url)
                : try FileStore.create(at: url, owner: owner)
            if remember {
                let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
                UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            }
            folderURL = url
            self.store = store
            problem = nil
            shared.update(store: store)
            keepFresh(store)
            refreshSummary()
        } catch {
            problem = "Could not open the notebook in \(url.lastPathComponent): \(error)"
        }
    }

    /// The folder is watched, so a line the phone writes shows here on its own. When the
    /// folder is in iCloud Drive, iCloud is asked to say when a file has a newer version,
    /// and the bytes are pulled down the moment it does.
    private func keepFresh(_ store: FileStore) {
        watcher = FolderWatcher(directory: store.eventsDirectory) { [weak self] in
            self?.refreshSummarySoon()
        }
        cloud = CloudWatcher(store: store) { [weak self] in
            self?.refreshSummarySoon()
        }
    }

    private func refreshSummarySoon() {
        summaryTask?.cancel()
        summaryTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.refreshSummary()
        }
    }

    func refreshSummary() {
        guard let store, let read = try? store.loadFiles() else {
            summary = ""
            self.notebook = nil
            inbox = []
            grants = []
            keysRefused = nil
            return
        }
        let files = read.map { (file: $0.name, events: $0.events) }
        let notebook = Notebook(owner: store.manifest.owner, events: files.flatMap(\.events))
        self.notebook = notebook
        inbox = Core.Inbox.items(files: files, notebook: notebook, calendar: .current)
        var refused: OSStatus?
        grants = notebook.grants.map { grant in
            var held = grant
            switch GrantKeys.look(for: grant.id) {
            case .key(let key): held.key = key
            case .none: held.key = ""
            case .refused(let status): held.key = ""; refused = status
            }
            return held
        }
        keysRefused = refused.map { status in
            let why = SecCopyErrorMessageString(status, nil) as String? ?? "keychain \(status)"
            return "The keychain would not let this app read its keys: \(why). The keys are still there. Quit \(Identity.name) and open it again; an app built again while it runs is refused like this."
        }
        // The loops as the notebook has them now; then something changed in the folder, so
        // each one woken by lines looks, a moment later.
        syncLoops(store, notebook)
        for runner in runners.values { runner.wake(store) }
        pushAddresses = (try? store.pushAddresses()) ?? []
        scheduleDuePushes(notebook)
        openWhatLinesPointAt(store, notebook)
        let days = notebook.days(calendar: .current)
        var text = "\(notebook.entries.count) lines over \(days.count) days"
        if let last = days.last?.key { text += " · last \(last)" }
        // Photos the door would refuse until iCloud brings them.
        if let arriving = cloud?.state?.arriving, arriving > 0 { text += " · \(arriving) media files not yet on this Mac" }
        if let trouble = cloud?.state?.trouble { text += " · iCloud: \(trouble)" }
        // Damage is passed over, never hidden: which file, which lines.
        for file in read where !file.unreadable.isEmpty {
            let lines = file.unreadable.map(String.init).joined(separator: ", ")
            text += " · \(file.name): line\(file.unreadable.count == 1 ? "" : "s") \(lines) could not be read and \(file.unreadable.count == 1 ? "was" : "were") passed over"
        }
        summary = text
    }

    /// Only used when the Mac starts a new notebook. Opening one made on the phone keeps the phone's owner.
    private var owner: Author {
        if let raw = UserDefaults.standard.string(forKey: ownerKey) { return Author(rawValue: raw) }
        let raw = "me-" + String(ULID().string.suffix(6)).lowercased()
        UserDefaults.standard.set(raw, forKey: ownerKey)
        return Author(rawValue: raw)
    }

    /// This Mac, as the owner's events written here name it. Made once.
    private var device: DeviceID {
        if let raw = UserDefaults.standard.string(forKey: deviceKey) { return DeviceID(rawValue: raw) }
        let raw = "mac-" + String(ULID().string.suffix(4)).lowercased()
        UserDefaults.standard.set(raw, forKey: deviceKey)
        return DeviceID(rawValue: raw)
    }

    /// An event of the owner's, from this Mac, into the owner's file for it.
    @discardableResult
    private func write(_ payload: Payload) -> Bool {
        guard let store else { return false }
        let now = Date()
        do {
            try store.append(Event(id: generator.next(at: now), author: store.manifest.owner, device: device, at: now, payload: payload))
            refreshSummary()
            return true
        } catch {
            problem = "Could not write to the notebook: \(error)"
            return false
        }
    }

    // MARK: - What the owner's lines point at

    /// What has been tried since the app opened, so an address that would not open is not
    /// asked for again and again.
    private var opened: Set<String> = []

    /// The owner wrote a line with a link in it: this Mac, the owner's own, opens exactly
    /// that address and keeps its words beside the line, as the owner's event from here.
    /// Only the owner's own lines, only the last day's, each address once. What is kept
    /// wakes the reading like anything that lands, and it reads the page as part of the line.
    private func openWhatLinesPointAt(_ store: FileStore, _ notebook: Notebook) {
        for (entry, url) in notebook.unopened(since: Date().addingTimeInterval(-86_400)) {
            guard opened.insert("\(entry)|\(url.absoluteString)").inserted else { continue }
            Task { [weak self] in
                guard let page = await Opener.open(url), let self, self.store?.root == store.root else { return }
                do {
                    let hash = try store.storeMedia(Data(page.kept(from: url).utf8), fileExtension: "md")
                    self.write(.mediaAttach(.init(entry: entry, hash: hash, mime: "text/markdown", title: page.title, source: url.absoluteString)))
                } catch {
                    self.problem = "Could not keep \(url.absoluteString): \(error)"
                }
            }
        }
    }

    // MARK: - Lines written here

    /// A picture that landed in the live line on this Mac, kept in the notebook's media by
    /// its hash. Nil when there is no notebook or it could not be written.
    func keepPicture(_ picture: Core.Picture.Processed) -> String? {
        try? store?.storeMedia(picture.jpeg, fileExtension: "jpg")
    }

    /// Where a kept picture is, for the live line to show it again after a relaunch.
    func mediaURL(hash: String) -> URL? {
        store?.mediaURL(hash: hash, fileExtension: "jpg")
    }

    /// Return, on the Mac: the live line stored as one line of yours, from this Mac, in the
    /// owner's file for it. The Mac keeps no place. Nil when there was nothing to store or it
    /// could not be written.
    func keep(_ draft: Draft) -> ULID? {
        guard let store, let stored = draft.stored(by: store.manifest.owner, on: device, here: nil, ids: generator,
                                                   now: Date(), calendar: .current) else { return nil }
        do {
            try store.append(stored.events)
            refreshSummary()
            return stored.id
        } catch {
            problem = "Could not write to the notebook: \(error)"
            return nil
        }
    }

    /// The loop that is running right now, by name, if one is.
    var runningLoop: String? {
        _ = readerTick
        return loops.first { runners[$0.id]?.status.state == .running }?.name
    }

    // MARK: - Grants

    private var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Identity.supportFolder, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Everyone who has written anything other than the owner, named where they have chosen
    /// a name: the authors a new key could be handed to.
    var authors: [Author] {
        notebook?.others ?? []
    }

    /// A new grant: a key for an author. A new author gets a fresh id and no name, and
    /// chooses one through the door when it wants to. An existing author gets one more key,
    /// the same being from another hand or another machine. The key goes to the keychain, the
    /// grant into the notebook as the owner's event; the fold then shows it.
    func addGrant(name: String, as author: Author? = nil) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        open(Grant(name: cleanName, author: author ?? .fresh(), device: Grant.device(for: cleanName)))
    }

    /// False when the key could not be kept or the grant could not be written: then there
    /// is no such grant, and nothing may be done that counts on it.
    @discardableResult
    private func open(_ grant: Grant) -> Bool {
        do {
            try GrantKeys.save(grant.key, for: grant.id)
        } catch {
            problem = "Could not keep the key in the keychain: \(error.localizedDescription)"
            return false
        }
        guard write(.grantCreate(grant.create)) else {
            GrantKeys.remove(for: grant.id)
            return false
        }
        return true
    }

    /// The owner's word that one originator is another: everything it did, and does from now
    /// on, is the other's. Nothing is rewritten; the fold reads through it. A key it holds
    /// opens the door as the other from the next request.
    func declare(_ author: Author, sameAs other: Author) {
        guard let owner = store?.manifest.owner, author != owner, other != owner, author != other else { return }
        write(.same(.init(author: author, as: other)))
    }

    /// What an author is called, if they have chosen; else their id.
    func name(of author: Author) -> String {
        notebook?.name(of: author) ?? author.rawValue
    }

    /// The key stops opening the door. The author's events stay, under their id. Loops that
    /// ran under it stop with it.
    func revoke(_ grant: Grant) {
        moveLoops(from: grant.id, to: nil)
        write(.grantRevoke(.init(grant: grant.id)))
        GrantKeys.remove(for: grant.id)
    }

    /// Loops set to run under one grant follow it to another, or stop when it goes.
    private func moveLoops(from old: ULID, to new: ULID?) {
        for loop in loops where loop.grant == old {
            if let new {
                set(loop, under: new)
            } else {
                write(.loopStop(.init(loop: loop.id)))
            }
        }
    }

    /// The same loop, its name, what wakes it and its brief as they are, under another grant.
    private func set(_ loop: Loop, under grant: ULID) {
        var at: String?
        var kind = "line"
        if case .clock(let hour, let minute) = loop.wake { kind = "clock"; at = String(format: "%02d:%02d", hour, minute) }
        write(.loopSet(.init(loop: loop.id, name: loop.name, grant: grant, wake: kind, at: at, brief: loop.brief, turns: loop.turns, budget: loop.budget)))
    }

    /// A loop whose grant is gone is given another, and runs again as it was.
    func run(_ loop: Loop, as grant: Grant) {
        set(loop, under: grant.id)
    }

    /// The same key, another author: whoever holds it is that author from now on. The old
    /// grant is closed and a new one opened with the same hash, so nothing has to be pasted
    /// again. For a key handed out before an author had the page it should have had.
    func reassign(_ grant: Grant, to author: Author) {
        guard author != grant.author else { return }
        var moved = Grant(name: grant.name, author: author, device: grant.device, key: grant.key,
                          writesNotes: grant.writesNotes, writesLabels: grant.writesLabels, writesLinks: grant.writesLinks, writesLines: grant.writesLines)
        moved.keyHash = grant.keyHash
        write(.grantRevoke(.init(grant: grant.id)))
        if !grant.key.isEmpty { try? GrantKeys.save(grant.key, for: moved.id) }
        GrantKeys.remove(for: grant.id)
        write(.grantCreate(moved.create))
        moveLoops(from: grant.id, to: moved.id)
    }

    /// A fresh key for the same author, for when this Mac no longer holds the old one.
    /// The new key first. Until it is kept and its grant written, the old one stands and
    /// its loops stay with it: closing the old grant first once left loops under a grant
    /// that was never made.
    func reissue(_ grant: Grant) {
        let fresh = Grant(name: grant.name, author: grant.author, device: grant.device,
                          writesNotes: grant.writesNotes, writesLabels: grant.writesLabels, writesLinks: grant.writesLinks, writesLines: grant.writesLines)
        guard open(fresh) else { return }
        moveLoops(from: grant.id, to: fresh.id)
        write(.grantRevoke(.init(grant: grant.id)))
        GrantKeys.remove(for: grant.id)
    }

    /// What the person pastes into a terminal so Claude Code knows the door and the key.
    /// Nil when this Mac does not hold the key.
    func connectCommand(for grant: Grant) -> String? {
        guard !grant.key.isEmpty else { return nil }
        return "claude mcp add --transport http \(Identity.serverName) http://127.0.0.1:\(port ?? Self.defaultPort)/mcp --header \"Authorization: Bearer \(grant.key)\""
    }

    // MARK: - Pushes

    /// The `.p8` Apple hands out once, named AuthKey_<id>.p8. The id is read from the name,
    /// the team from this app's own signing. The key goes into the keychain.
    func choosePushKey() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use This Key"
        panel.message = "Pick the push key downloaded from the developer account, AuthKey_<id>.p8."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let keyID = PushKey.keyID(fromFileName: url.lastPathComponent) else {
            pushReport = "The file should be named as Apple named it, AuthKey_<id>.p8, so the key's id is known."
            return
        }
        guard let teamID = Bundle.main.object(forInfoDictionaryKey: "DottoTeamID") as? String, !teamID.isEmpty else {
            pushReport = "This build carries no team id, so the claim could not be signed."
            return
        }
        do {
            let pem = try String(contentsOf: url, encoding: .utf8)
            // Refuse early what Apple would refuse later.
            _ = try APNS.token(for: PushKey(keyID: keyID, teamID: teamID, pem: pem))
            let key = PushKey(keyID: keyID, teamID: teamID, pem: pem)
            try PushKeyStore.save(key)
            pushKey = key
            pushReport = nil
            Task { await pusher.use(key) }
        } catch {
            pushReport = "Could not take the key: \(error.localizedDescription)"
        }
    }

    func removePushKey() {
        PushKeyStore.remove()
        pushKey = nil
        pushReport = nil
        Task { await pusher.use(nil) }
    }

    /// One push to every phone, to see it arrive.
    func sendTestPush() {
        push(APNS.Message(title: "dotto", body: "Pushes reach this phone."))
    }

    /// Words written through the door go to the phone as a push: a note under a line, a line
    /// on the writer's own page, a name chosen. Marks stay silent: labels and links are for
    /// the page, not the pocket. The push is titled with the writer's name once it has one.
    nonisolated private func pushIfWords(_ event: Event) {
        Task { @MainActor in
            let title = self.notebook?.name(of: event.author) ?? "dotto"
            switch event.payload {
            case .noteAdd(let note):
                self.push(APNS.Message(title: title, body: note.text, entry: note.entry))
            case .entryCreate(let line):
                // A reply opens the line whose conversation it is in; a line opens itself.
                let opens = line.under.map { self.notebook?.note($0)?.entry.id ?? $0 } ?? line.entry
                self.push(APNS.Message(title: title, body: line.text, entry: opens))
            case .nameSet(let chosen):
                self.push(APNS.Message(title: "dotto", body: "Chose the name \(chosen.name)."))
            default:
                break
            }
        }
    }

    /// `unless` is a moment's key, for a push about one: a phone that has set its own notice
    /// for that moment is not sent another.
    private func push(_ message: APNS.Message, unless covered: String? = nil) {
        guard pushKey != nil else {
            pushReport = "No push key on this Mac yet."
            return
        }
        let all = (try? store?.pushAddresses()) ?? []
        let addresses = all.filter { address in covered.map { address.scheduled?.contains($0) != true } ?? true }
        if !all.isEmpty, addresses.isEmpty {
            pushReport = "The phone says this one itself."
            return
        }
        guard !addresses.isEmpty else {
            pushReport = "No phone has written its address to the folder yet. Allow notifications in the phone's Setup."
            return
        }
        Task {
            let outcomes = await pusher.send(message, to: addresses)
            // An address Apple says is no longer that phone's is forgotten: the app was deleted
            // or put on again, and when it is back it writes a new one.
            for outcome in outcomes where outcome.gone { try? store?.removePushAddress(of: outcome.device) }
            pushReport = outcomes.map { outcome in
                if outcome.ok { return "Sent to \(outcome.device.rawValue)." }
                if outcome.gone { return "\(outcome.device.rawValue) is no longer reachable; its address is forgotten." }
                return "\(outcome.device.rawValue): \(outcome.reason ?? "refused")."
            }.joined(separator: " ")
        }
    }

    // MARK: - Due moments

    private var dueTimers: [String: DispatchWorkItem] = [:]
    private let dueSentKey = Identity.Kept.dueSent

    /// A fact is silent when it lands; a due moment speaks once, when it comes. For every
    /// line of the owner's with a due moment still ahead and not done, a push at that moment
    /// with the line's words. Rescheduled from the fold each time the folder changes, so a
    /// moment moved or taken off never fires; what was sent is remembered across launches so
    /// nothing fires twice. A moment already past when the Mac wakes is not sent late.
    private func scheduleDuePushes(_ notebook: Notebook) {
        for item in dueTimers.values { item.cancel() }
        dueTimers = [:]
        let now = Date()
        var sent = Set(UserDefaults.standard.stringArray(forKey: dueSentKey) ?? [])
        for entry in notebook.due(after: now) {
            guard let due = entry.due else { continue }
            let key = "\(entry.id)|\(Int(due.timeIntervalSince1970))"
            guard !sent.contains(key) else { continue }
            let item = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    // The Mac slept through the moment: it is not sent late.
                    guard Date().timeIntervalSince(due) < 60 else { self.dueTimers[key] = nil; return }
                    var sent = Set(UserDefaults.standard.stringArray(forKey: self.dueSentKey) ?? [])
                    guard sent.insert(key).inserted else { return }
                    UserDefaults.standard.set(Array(sent), forKey: self.dueSentKey)
                    self.dueTimers[key] = nil
                    self.push(APNS.Message(title: "Due now", body: entry.text.isEmpty ? "a photo" : entry.text, entry: entry.id),
                              unless: Notice.key(entry: entry.id, moment: due))
                }
            }
            dueTimers[key] = item
            // By the clock on the wall, which keeps counting while the Mac sleeps.
            DispatchQueue.main.asyncAfter(wallDeadline: .now() + due.timeIntervalSince(now), execute: item)
        }
        // What was sent is kept only while its moment is still in the notebook.
        let alive = Set(notebook.entries.flatMap { entry in
            entry.facts("due").compactMap { fact -> String? in
                guard case .moment(let at) = fact.value else { return nil }
                return "\(entry.id)|\(Int(at.timeIntervalSince1970))"
            }
        })
        sent.formIntersection(alive)
        UserDefaults.standard.set(Array(sent), forKey: dueSentKey)
    }

    // MARK: - Loops

    private var readerRunsURL: URL { supportDirectory.appendingPathComponent(ReaderFiles.runs, isDirectory: true) }
    var readerLogURL: URL { supportDirectory.appendingPathComponent(ReaderFiles.log) }

    /// The loops the notebook says run today, oldest first.
    var loops: [Loop] { notebook?.loops ?? [] }

    func status(of loop: Loop) -> ReaderStatus? { runner(of: loop)?.status }
    func runs(of loop: Loop) -> [ReaderRun] { runner(of: loop)?.runs ?? [] }
    /// What runs a loop. A sentence woken by a line is run by the one reading it is part
    /// of, with the other such sentences; a loop on the clock by itself.
    func runner(of loop: Loop) -> ReaderRunner? {
        _ = readerTick
        return runners[notebook?.reading(holding: loop)?.id ?? loop.id]
    }

    /// A loop is the owner's event in the notebook. Set once here; every device holding the
    /// folder knows it, and this Mac, the home, runs it.
    func addLoop(name: String, grant: Grant, wake: Loop.Wake, brief: String) {
        guard let store else { return }
        let at: String?
        let kind: String
        switch wake {
        case .line: kind = "line"; at = nil
        case .clock(let hour, let minute): kind = "clock"; at = String(format: "%02d:%02d", hour, minute)
        }
        let words = brief.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        let id = generator.next(at: now)
        try? store.append(Event(id: id, author: store.manifest.owner, device: device, at: now,
                                payload: .loopSet(.init(loop: id, name: name.trimmingCharacters(in: .whitespaces), grant: grant.id,
                                                        wake: kind, at: at, brief: words.isEmpty ? nil : words))))
        refreshSummary()
    }

    /// The loop stops: an event of the owner's, and the runner goes.
    func stopLoop(_ loop: Loop) {
        stop(loop.id)
    }

    /// A proposal taken: the loop set under the proposal's id, as the proposer's grant.
    func takeProposal(_ proposal: LoopProposal) {
        guard let store, let grant = proposal.grant, grants.contains(where: { $0.id == grant }) else { return }
        let now = Date()
        try? store.append(Event(id: generator.next(at: now), author: store.manifest.owner, device: device, at: now,
                                payload: .loopSet(.init(loop: proposal.id, name: proposal.name, grant: grant, wake: proposal.wake.kind,
                                                        at: proposal.wake.at, brief: proposal.brief, turns: proposal.turns, budget: proposal.budget))))
        refreshSummary()
    }

    /// A proposal declined: a stop of its id before any set.
    func declineProposal(_ proposal: LoopProposal) {
        stop(proposal.id)
    }

    private func stop(_ id: ULID) {
        guard let store else { return }
        let now = Date()
        try? store.append(Event(id: generator.next(at: now), author: store.manifest.owner, device: device, at: now,
                                payload: .loopStop(.init(loop: id))))
        refreshSummary()
    }

    /// The app is quitting: every loop's session is ended with it.
    func stopLoops() {
        for runner in runners.values { runner.stop() }
    }

    /// Looks now, whatever wakes the loop, and runs even with nothing new.
    func lookNow(_ loop: Loop) {
        runner(of: loop)?.lookNow()
    }

    /// Runners follow the notebook: one per loop that runs, made when the loop appears or is
    /// set again, gone when it is stopped. A loop whose grant has no key on this Mac waits,
    /// and the window says so.
    private func syncLoops(_ store: FileStore, _ notebook: Notebook) {
        guard Identity.runsLoops else { return }
        // A loop reads through this app's own door. While that is not open nothing runs:
        // the port may be another home's, and the lines would be answered twice.
        guard case .open = door else {
            for runner in runners.values { runner.stop() }
            runners = [:]
            readerTick += 1
            return
        }
        // What runs is not the loops one by one: the sentences woken by a line are one reading.
        let running = notebook.running
        let wanted = Dictionary(uniqueKeysWithValues: running.map { ($0.id, $0) })
        for (id, runner) in runners where wanted[id].map({ !$0.sameWork(as: runner.loop) }) ?? true {
            runner.stop()
            runners[id] = nil
        }
        for loop in running where runners[loop.id] == nil {
            guard let grant = grants.first(where: { $0.id == loop.grant }), !grant.key.isEmpty else { continue }
            let runner = ReaderRunner(loop: loop, grant: grant, door: "http://127.0.0.1:\(Self.defaultPort)/mcp", model: readerModel,
                                      runsDirectory: readerRunsURL, logURL: readerLogURL)
            runner.onChange = { [weak self] in self?.readerTick += 1 }
            runner.onRan = { [weak self, weak runner] run in
                guard let self, let runner, let endedAt = run.endedAt else { return }
                // The receipt, in the notebook, under the loop's own originator and the reader's hand.
                try? store.append(Event(id: self.generator.next(at: endedAt), author: runner.grant.author, device: runner.loop.hand, at: endedAt,
                                        payload: .loopRan(.init(loop: runner.loop.id, run: run.id, ok: run.ok ?? false, turns: run.turns,
                                                                cost: run.costUSD, summary: run.summary, startedAt: run.startedAt, endedAt: endedAt))))
            }
            runner.remember(store)
            runners[loop.id] = runner
        }
        readerTick += 1
    }

    // MARK: - The door

    private func openDoor() async {
        let shared = self.shared
        let router = DoorRouter(calendar: .current, resolve: { key in shared.resolve(key) },
                                written: { [weak self] event in self?.pushIfWords(event) })
        do {
            let server = try DoorServer(port: Self.defaultPort) { router.respond($0) }
            self.server = server
            door = .open(try await server.start())
            // The door is open: the loops start, and look.
            refreshSummary()
        } catch {
            door = .failed(Identity.carriesOver && CarryOver.earlierIsRunning
                ? "The earlier dotto is still running on this Mac and holds the door. Quit it, then open this one again."
                : "The door could not open on port \(Self.defaultPort): \(error)")
        }
    }
}

/// What the server thread may see: the current store, behind a lock. A key is looked up in
/// the fold of that store, so the grants are whatever the notebook says at that moment.
final class DoorState: @unchecked Sendable {
    private let lock = NSLock()
    private var store: FileStore?

    func update(store: FileStore?) {
        lock.lock()
        self.store = store
        lock.unlock()
    }

    func resolve(_ key: String) -> (FileStore, Grant)? {
        lock.lock()
        let store = self.store
        lock.unlock()
        guard let store, let grant = try? store.load().grant(forKey: key) else { return nil }
        return (store, grant)
    }
}

/// The keys this Mac holds, one per grant, in the keychain. The notebook has only hashes.
enum GrantKeys {
    private static let service = Identity.keychainService("grant-keys")

    /// What the keychain says of one grant's key. Not being let in is not the same as there
    /// being no key: a key that is refused is still there, and is not to be replaced.
    enum Held {
        case key(String)
        case none
        case refused(OSStatus)
    }

    static func look(for grant: ULID) -> Held {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: grant.string,
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return .none }
        guard status == errSecSuccess else { return .refused(status) }
        guard let data = item as? Data, let key = String(data: data, encoding: .utf8) else { return .none }
        return .key(key)
    }

    static func save(_ key: String, for grant: ULID) throws {
        remove(for: grant)
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: grant.string,
            kSecValueData as String: Data(key.utf8),
        ]
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: SecCopyErrorMessageString(status, nil) as String? ?? "keychain \(status)"])
        }
    }

    static func remove(for grant: ULID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: grant.string,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
