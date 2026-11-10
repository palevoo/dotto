import Core
import PhotosUI
import SwiftUI
import UIKit

/// The page. Days scroll up into the past; the live line waits at the bottom, always;
/// the date is pinned above. Tap a line to open it, tap a photo to see it.
struct PageView: View {
    @Bindable var model: NotebookModel
    let onRelocate: (URL) -> Void
    @State private var path = NavigationPath()
    /// Where the page is: read for the pinned date, set to move it. The page opens at the
    /// bottom.
    @State private var position = ScrollPosition(edge: .bottom)
    /// A line just stored, which the page goes to once its row is on the page.
    @State private var landed: Landing?
    @State private var atBottom = true
    @State private var showCalendar = false
    /// What the calendar sheet asked for, done once it has gone: a page is pushed on a
    /// clear stage.
    @State private var afterCalendar: Route?
    @State private var showCamera = false
    @State private var picked: [PhotosPickerItem] = []
    @State private var viewing: PhotoOpening?
    @Namespace private var zoom
    @State private var revealed: ULID?
    /// Who has the keyboard on the page: nobody, the live line, or a line whose words are
    /// being changed where they stand. One at a time; a tap anywhere else takes it back.
    enum Keyboard: Equatable {
        case none
        case liveLine
        case row(ULID)
    }
    @State private var keyboard: Keyboard = .none
    @State private var launch = Launch.shared
    /// A line a push named that the fold does not hold yet: Apple carries the push faster
    /// than iCloud carries the line it is about. Opened the moment the line arrives.
    @State private var awaitedLine: ULID?
    @State private var recorder = VoiceRecorder()

    /// The live line's view of the keyboard: a field that mirrors its first-responder status.
    private var liveFocused: Binding<Bool> {
        Binding(get: { keyboard == .liveLine },
                set: { has in if has { keyboard = .liveLine } else if keyboard == .liveLine { keyboard = .none } })
    }

    /// The rows' view of the keyboard: the line being edited, if any.
    private var editingRow: Binding<ULID?> {
        Binding(get: { if case .row(let id) = keyboard { return id }; return nil },
                set: { id in if let id { keyboard = .row(id) } else if case .row = keyboard { keyboard = .none } })
    }

    /// The day of whatever row is at the top of the page.
    private var visibleDay: DayKey {
        switch position.viewID(type: Row.ID.self) {
        case .day(let key): key
        case .line(let id): model.notebook.entry(id).map { DayKey($0.startedAt, calendar: model.calendar) } ?? model.today
        case nil: model.today
        }
    }

    /// One row of the page: a day's rule with its date, or a line. The rows, not the days,
    /// are what the page lays out lazily and what it scrolls to. A whole day as one child
    /// has no height the page knows until it has been drawn, so the bottom of the page was
    /// worked out without a day only just begun and the first line of a day was never
    /// reached; a row is small, the last one is always drawn, and a line stored is gone to
    /// by its own id.
    private struct Row: Identifiable {
        enum ID: Hashable {
            case day(DayKey)
            case line(ULID)
        }
        let id: ID
        /// The line, for a line's row.
        var entry: Entry?
        /// Space above: between days, and above today, which has no rule of its own.
        var gap: CGFloat = 0
    }

    private var rows: [Row] {
        var rows: [Row] = []
        for (index, day) in days.enumerated() {
            let follows: CGFloat = index == 0 ? 0 : 18
            if day.key == model.today {
                for (place, entry) in day.entries.enumerated() {
                    rows.append(Row(id: .line(entry.id), entry: entry, gap: place == 0 ? follows : 0))
                }
            } else {
                rows.append(Row(id: .day(day.key), gap: follows))
                rows += day.entries.map { Row(id: .line($0.id), entry: $0) }
            }
        }
        return rows
    }

    /// The row a day begins with: its rule, or, for today, its first line.
    private func start(of day: DayKey) -> Row.ID? {
        guard day == model.today else { return .day(day) }
        return days.last { $0.key == day }?.entries.first.map { .line($0.id) }
    }

    /// A line just stored and where on the screen it should come to rest.
    private struct Landing: Equatable {
        let line: ULID
        let anchor: UnitPoint
    }
    private var awaitedArrived: Bool { awaitedLine.map { model.notebook.entry($0) != nil } ?? false }

    private var days: [Day] { model.days }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(rows) { row in
                            Group {
                                if let entry = row.entry {
                                    EntryRow(
                                        entry: entry,
                                        model: model,
                                        revealed: revealed == entry.id,
                                        editingRow: editingRow,
                                        onOpen: { open { path.append(entry.id) } },
                                        onOpenPhoto: { opening in open { viewing = opening } },
                                        zoom: zoom
                                    )
                                } else if case .day(let key) = row.id {
                                    DayDivider(day: key, calendar: model.calendar)
                                }
                            }
                            .padding(.top, row.gap)
                            .id(row.id)
                        }
                        if days.isEmpty {
                            Text("Nothing yet. The line below is yours.")
                                .font(Theme.serifSmall)
                                .foregroundStyle(Theme.muted)
                                .padding(20)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.bottom, 20)
                    .contentShape(Rectangle())
                    .onTapGesture { putKeyboardAway() }
                }
                .scrollPosition($position, anchor: .top)
                .defaultScrollAnchor(.bottom)
                // Asked for here, after the page has been given the new row, not in the same
                // breath as the line being stored.
                .onChange(of: landed) { _, landing in
                    guard let landing else { return }
                    landed = nil
                    withAnimation(Motion.settle) { position.scrollTo(id: Row.ID.line(landing.line), anchor: landing.anchor) }
                }
                .scrollDismissesKeyboard(.interactively)
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 2
                } action: { _, isAtBottom in
                    atBottom = isAtBottom
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    PinnedHeader(
                        day: visibleDay,
                        today: model.today,
                        calendar: model.calendar,
                        unread: model.unread,
                        onTap: { showCalendar = true },
                        onInbox: { open { path.append(Route.inbox) } },
                        onCopyDay: { copy(day: visibleDay) },
                        onCopyAll: { copyAll() }
                    )
                }

                // The live line is the last row of the page, a sibling of the scroll, so the
                // keyboard lifts it and a push and pop can never lose it.
                LiveLine(
                    model: model,
                    focused: liveFocused,
                    recorder: recorder,
                    onReturn: { storeDraft() },
                    onCamera: { showCamera = true },
                    onSpeak: { speak() },
                    onStopSpeaking: { finishVoice() }
                )
                .background(Theme.background)
                .overlay(alignment: .top) {
                    Theme.line.frame(height: 1).opacity(atBottom ? 0 : 1)
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .sheet(isPresented: $showCalendar, onDismiss: {
                guard let next = afterCalendar else { return }
                afterCalendar = nil
                path.append(next)
            }) {
                CalendarSheet(
                    days: model.days,
                    today: model.today,
                    calendar: model.calendar,
                    tags: model.notebook.tags,
                    kinds: model.notebook.kinds,
                    todos: model.notebook.todos.count,
                    lastVisit: model.notebook.visits.last { $0.author != model.store.manifest.owner }
                        .map { ($0.author, LogView.summary(of: $0, calendar: model.calendar)) },
                    others: model.notebook.others,
                    unread: model.unread,
                    model: model,
                    onPick: { key in
                        showCalendar = false
                        guard let start = start(of: key) else { return }
                        withAnimation(Motion.settle) { position.scrollTo(id: start, anchor: .top) }
                    },
                    onTag: { tag in
                        afterCalendar = .thing(tag)
                        showCalendar = false
                    },
                    onInbox: {
                        afterCalendar = .inbox
                        showCalendar = false
                    },
                    onSearch: {
                        afterCalendar = .search
                        showCalendar = false
                    },
                    onLog: {
                        afterCalendar = .log
                        showCalendar = false
                    },
                    onSetup: {
                        afterCalendar = .setup
                        showCalendar = false
                    },
                    onTodos: {
                        afterCalendar = .todos
                        showCalendar = false
                    },
                    onKind: { kind in
                        afterCalendar = .things(kind)
                        showCalendar = false
                    },
                    onAuthor: { author in
                        afterCalendar = .author(author)
                        showCalendar = false
                    }
                )
                .presentationBackground(Theme.paper)
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraView(picked: $picked) { shot in
                    showCamera = false
                    guard let shot else { return }
                    model.keepInPhotos(shot.data)
                    Task {
                        await model.addPhoto(shot.data)
                        if let quote = shot.quote { model.addQuote(quote) }
                        Haptic.touch()
                        keyboard = .liveLine
                    }
                }
            }
            .fullScreenCover(item: $viewing) { opening in
                PhotoViewer(opening: opening, model: model) { viewing = nil }
                    .ignoresSafeArea()
                    .navigationTransition(.zoom(sourceID: opening.id, in: zoom))
            }
            .onChange(of: picked) { _, items in
                guard !items.isEmpty else { return }
                showCamera = false
                Task {
                    // Into the live line, like the camera: the words come next, Return stores.
                    for item in items {
                        if let photo = await PhotoLibrary.load(item) {
                            await model.importPhoto(photo.data, takenAt: photo.takenAt, location: photo.location)
                        }
                    }
                    picked = []
                    Haptic.touch()
                    keyboard = .liveLine
                }
            }
            // Words wait in the line until Return, keyboard or not. Nothing else stores them.
            // Back on the page from a line or the inbox: a keyboard raised there has no field
            // here to belong to, so it goes.
            .onChange(of: path.count) { _, count in
                guard count == 0, keyboard == .none else { return }
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            // A press from outside: the Action button, a control, Siri. Back to the
            // page, then the line or the camera.
            .onChange(of: launch.request, initial: true) { _, request in
                guard let request else { return }
                launch.request = nil
                path = NavigationPath()
                viewing = nil
                showCalendar = false
                switch request {
                case .write: keyboard = .liveLine
                case .photo: showCamera = true
                case .speak: speak()
                case .line(let raw):
                    guard let id = ULID(raw) else { return }
                    if model.notebook.entry(id) != nil {
                        path.append(id)
                    } else {
                        awaitedLine = id
                    }
                }
            }
            .onChange(of: awaitedArrived) { _, arrived in
                guard arrived, let id = awaitedLine else { return }
                awaitedLine = nil
                path.append(id)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ULID.self) { id in
                LineView(entryID: id, model: model)
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .log: LogView(model: model)
                case .inbox: InboxView(model: model)
                case .setup: SetupView(model: model, onRelocate: onRelocate)
                case .author(let author): AuthorPage(author: author, model: model)
                case .thing(let id): ThingPage(id: id, model: model)
                case .loops: LoopsView(model: model)
                case .todos: TodosPage(model: model)
                case .things(let kind): ThingsPage(kind: kind, model: model)
                case .search: SearchPage(model: model)
                }
            }
        }
        .tint(Theme.accent)
    }

    /// With the keyboard up, the first tap anywhere on the page puts it away. Nothing opens
    /// until the next tap.
    private func open(_ action: () -> Void) {
        if keyboard != .none {
            putKeyboardAway()
        } else {
            action()
        }
    }

    /// Whoever has the keyboard, the live line or a line being edited, lets it go.
    private func putKeyboardAway() {
        keyboard = .none
    }

    /// Stores the live line and settles the page on it, one short motion. A line stored on an
    /// earlier day, from a photo's own moment, is shown where it landed.
    private func storeDraft() {
        var stored: ULID?
        withAnimation(Motion.settle) { stored = model.commitDraft() }
        guard let stored else { return }
        Haptic.store()
        let day = model.notebook.entry(stored).map { DayKey($0.startedAt, calendar: model.calendar) } ?? model.today
        if day == model.today {
            // Today's line comes to rest at the foot of the page, above the live line.
            landed = Landing(line: stored, anchor: .bottom)
        } else {
            reveal(stored)
        }
    }

    /// The page goes to the line itself, wherever its day is, and marks it for a moment.
    private func reveal(_ id: ULID) {
        landed = Landing(line: id, anchor: .center)
        withAnimation(Motion.settle) { revealed = id }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut(duration: 0.8)) {
                if revealed == id { revealed = nil }
            }
        }
    }

    private func speak() {
        guard !recorder.isRecording else { return }
        if keyboard == .liveLine { keyboard = .none }
        Haptic.touch()
        Task { await recorder.start() }
    }

    /// The take lands in the live line: the words as text to fix, the audio behind them.
    private func finishVoice() {
        guard let take = recorder.stop() else { return }
        Haptic.touch()
        // The audio is in the line before its words are made; the words follow.
        guard let kept = model.addVoice(fileURL: take.fileURL, duration: take.duration, startedAt: take.startedAt) else { return }
        keyboard = .liveLine
        Task {
            let transcript = await Voice.transcribe(kept.url)
            model.addWords(transcript, ofVoice: kept.hash)
        }
    }

    /// The day as the same markdown the folder holds.
    private func copy(day key: DayKey) {
        guard let day = model.days.first(where: { $0.key == key }) else { return }
        UIPasteboard.general.string = Projector.markdown(for: day, calendar: model.calendar, names: model.notebook.chosenNames)
    }

    private func copyAll() {
        UIPasteboard.general.string = model.days
            .map { Projector.markdown(for: $0, calendar: model.calendar, names: model.notebook.chosenNames) }
            .joined(separator: "\n")
    }
}

enum Motion {
    /// One short, calm curve for everything that moves on the page.
    static let settle: Animation = .snappy(duration: 0.28, extraBounce: 0)
}

/// The date, pinned. Tap it for the calendar; hold it to copy the day as text. When
/// something arrived for you since you last looked, its count stands at the end; tap it
/// for the inbox.
struct PinnedHeader: View {
    let day: DayKey
    let today: DayKey
    let calendar: Calendar
    let unread: Int
    let onTap: () -> Void
    let onInbox: () -> Void
    let onCopyDay: () -> Void
    let onCopyAll: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button(action: onTap) {
                // The date is the one header; tap it for the calendar and everything else.
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(label)
                        .font(Theme.title)
                        .foregroundStyle(Theme.foreground)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.faint)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("date")
            .contextMenu {
                Button("Copy this day", systemImage: "doc.on.doc", action: onCopyDay)
                Button("Copy every day", systemImage: "doc.on.doc.fill", action: onCopyAll)
            }
            Spacer()
            if unread > 0 {
                Button(action: onInbox) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 6, height: 6)
                        Text("\(unread)")
                            .font(Theme.mono)
                            .foregroundStyle(Theme.accent)
                            .monospacedDigit()
                    }
                    .frame(height: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Inbox, \(unread) new")
            }
            if day != today {
                Text(relative)
                    .font(Theme.mono)
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 12)
        // Opaque, and up under the status bar too, so lines scrolling beneath never show through.
        .background(Theme.background.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
    }

    private var label: String {
        guard let date = day.date(in: calendar) else { return day.description }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale
        formatter.setLocalizedDateFormatFromTemplate(day.year == today.year ? "EEE d MMM" : "EEE d MMM yyyy")
        return formatter.string(from: date)
    }

    private var relative: String {
        guard let from = day.date(in: calendar), let to = today.date(in: calendar),
              let days = calendar.dateComponents([.day], from: from, to: to).day else { return "" }
        switch days {
        case 1: return "Yesterday"
        case 2...13: return "\(days) days ago"
        case 14...60: return "\(days / 7) weeks ago"
        default: return "\(days) days ago"
        }
    }
}

/// A quiet rule with the date, between days when scrolling up.
struct DayDivider: View {
    let day: DayKey
    let calendar: Calendar

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(Theme.mono)
                .foregroundStyle(Theme.muted)
            Theme.line.frame(height: 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    private var label: String {
        guard let date = day.date(in: calendar) else { return day.description }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return formatter.string(from: date)
    }
}

/// The last row of the page, always in reach: the composer. The margin shows the
/// current minute until the first thing arrives, then keeps that moment. Photos from
/// before offer their own moment there; tap it to choose between then and now. Return
/// stores the line. The camera and the mic wait at its end while it is empty; while
/// speaking, a red square and the time stand there, and a tap on them stops.
struct LiveLine: View {
    @Bindable var model: NotebookModel
    @Binding var focused: Bool
    let recorder: VoiceRecorder
    let onReturn: () -> Void
    let onCamera: () -> Void
    let onSpeak: () -> Void
    let onStopSpeaking: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TimelineView(.everyMinute) { context in
                let moment = model.draftMoment ?? context.date
                let offersMoment = model.draftPhotoMoment != nil
                VStack(alignment: .leading, spacing: 3) {
                    Text(Format.time(moment, calendar: model.calendar))
                        .font(Theme.mono)
                        .foregroundStyle(Theme.muted)
                        .monospacedDigit()
                    if offersMoment {
                        Text(model.draftKeepsPhotoMoment ? Format.shortDay(moment, calendar: model.calendar) : "today")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(model.draftKeepsPhotoMoment ? Theme.accent : Theme.faint)
                            .transition(.opacity)
                    }
                }
                .frame(width: 44, alignment: .leading)
                .padding(.top, 6)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard offersMoment else { return }
                    Haptic.touch()
                    withAnimation(Motion.settle) { model.toggleDraftMoment() }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                if !model.draftMedia.isEmpty {
                    DraftMediaRow(model: model)
                }
                // Return stores; a pasted passage waits in the line like typed words.
                WordsField(placeholder: "", text: $model.draftText, identifier: "live-line", focused: $focused) { onReturn() }
            }
            if recorder.isRecording, let started = recorder.startedAt {
                Button(action: onStopSpeaking) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Theme.recording)
                            .frame(width: 12, height: 12)
                        TimelineView(.periodic(from: started, by: 1)) { context in
                            Text(Format.duration(context.date.timeIntervalSince(started)))
                                .font(Theme.mono)
                                .foregroundStyle(Theme.foreground)
                                .monospacedDigit()
                        }
                    }
                    .frame(height: 36)
                    .padding(.horizontal, 8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop")
                .transition(.opacity)
            } else if model.draftText.isEmpty {
                // Camera and mic wait at the end of an empty line and step aside once words
                // start, so the words get the same width as every line above.
                HStack(spacing: 4) {
                    Button(action: onCamera) {
                        Image(systemName: "camera")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Photo")
                    Button(action: onSpeak) {
                        Image(systemName: "mic")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Speak")
                }
                .transition(.opacity)
            }
        }
        .animation(Motion.settle, value: model.draftText.isEmpty)
        .animation(Motion.settle, value: recorder.isRecording)
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !focused else { return }
            Haptic.touch()
            focused = true
        }
    }
}

/// What has landed in the live line before its words. Each has an x at its corner to take it
/// out again.
struct DraftMediaRow: View {
    let model: NotebookModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(model.draftMedia) { item in
                    Group {
                        if item.mime.hasPrefix("image") {
                            ThumbView(hash: item.hash, original: model.mediaURL(item), side: 96)
                        } else {
                            VoiceChip(hash: item.hash, duration: item.duration ?? 0, url: model.mediaURL(item))
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        Button {
                            Haptic.touch()
                            withAnimation(Motion.settle) { model.removeDraftMedia(item) }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.background)
                                .frame(width: 22, height: 22)
                                .background(Theme.square(22).fill(Theme.foreground.opacity(0.85)))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 6, y: -6)
                        .accessibilityLabel("Take out")
                    }
                }
            }
            .padding(.top, 6)
            .padding(.trailing, 6)
        }
        .scrollClipDisabled()
    }
}


enum Format {
    static func time(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    /// "0.5×", "1×", "2.3×", as the system camera shows it.
    static func zoom(_ factor: Double) -> String {
        let rounded = (factor * 10).rounded() / 10
        let text = rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
        return text + "×"
    }

    /// "41.1496° N · 8.6109° W".
    static func place(_ location: Location) -> String {
        String(format: "%.4f° %@ · %.4f° %@",
               abs(location.latitude), location.latitude >= 0 ? "N" : "S",
               abs(location.longitude), location.longitude >= 0 ? "E" : "W")
    }

    /// "17 Oct", for the margin.
    static func shortDay(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter.string(from: date)
    }

    static func day(_ key: DayKey, calendar: Calendar, withYear: Bool = true) -> String {
        guard let date = key.date(in: calendar) else { return key.description }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale
        formatter.setLocalizedDateFormatFromTemplate(withYear ? "EEEE d MMMM yyyy" : "EEEE d MMMM")
        return formatter.string(from: date)
    }
}
