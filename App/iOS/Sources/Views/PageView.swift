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
    @State private var visibleDay: DayKey?
    @State private var atBottom = true
    @State private var showCalendar = false
    @State private var showMove = false
    @State private var showCamera = false
    @State private var picked: [PhotosPickerItem] = []
    @State private var viewing: PhotoOpening?
    @State private var filter: String?
    @State private var revealed: ULID?
    @State private var launch = Launch.shared
    @Namespace private var zoom
    @FocusState private var liveFocused: Bool

    private var days: [Day] {
        if let filter {
            return model.notebook.days(labelled: filter, calendar: model.calendar)
        }
        return model.days
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(days) { day in
                                DaySection(
                                    day: day,
                                    model: model,
                                    isToday: filter == nil && day.key == model.today,
                                    zoom: zoom,
                                    revealed: revealed,
                                    onOpen: { id in open { path.append(id) } },
                                    onOpenPhoto: { id, index in open { viewing = PhotoOpening(entry: id, index: index) } }
                                )
                                .id(day.key)
                            }
                            if days.isEmpty {
                                Text(filter == nil ? "Nothing yet. The line below is yours." : "Nothing filed here yet.")
                                    .font(Theme.serifSmall)
                                    .foregroundStyle(Theme.muted)
                                    .padding(20)
                            }
                        }
                        .scrollTargetLayout()
                        .padding(.bottom, 12)
                        .contentShape(Rectangle())
                        .onTapGesture { liveFocused = false }
                    }
                    .scrollPosition(id: $visibleDay, anchor: .top)
                    .defaultScrollAnchor(.bottom)
                    .scrollDismissesKeyboard(.interactively)
                    .onScrollGeometryChange(for: Bool.self) { geometry in
                        geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 2
                    } action: { _, isAtBottom in
                        atBottom = isAtBottom
                    }
                    .safeAreaInset(edge: .top, spacing: 0) {
                        PinnedHeader(
                            day: visibleDay ?? model.today,
                            today: model.today,
                            calendar: model.calendar,
                            filter: filter,
                            onTap: { showCalendar = true },
                            onClearFilter: { withAnimation(Motion.settle) { filter = nil } },
                            onCopyDay: { copy(day: visibleDay ?? model.today) },
                            onCopyAll: { copyAll() }
                        )
                    }

                    // The live line is the last row of the page, a sibling of the scroll, so the
                    // keyboard lifts it and a push and pop can never lose it.
                    LiveLine(
                        model: model,
                        focused: $liveFocused,
                        onReturn: { storeDraft(proxy) },
                        onCamera: { showCamera = true }
                    )
                    .background(Theme.background)
                    .overlay(alignment: .top) {
                        Theme.line.frame(height: 1).opacity(atBottom ? 0 : 1)
                    }
                }
                .background(Theme.background.ignoresSafeArea())
                .sheet(isPresented: $showCalendar) {
                    CalendarSheet(
                        days: model.days,
                        today: model.today,
                        calendar: model.calendar,
                        labels: model.notebook.labelCounts,
                        filter: filter,
                        home: Library.describe(model.store),
                        onPick: { key in
                            showCalendar = false
                            withAnimation(Motion.settle) { proxy.scrollTo(key, anchor: .top) }
                        },
                        onFilter: { label in
                            showCalendar = false
                            withAnimation(Motion.settle) { filter = label }
                        },
                        onMove: {
                            showCalendar = false
                            showMove = true
                        }
                    )
                    .presentationBackground(Theme.paper)
                }
                .sheet(isPresented: $showMove) {
                    FolderPicker { url in
                        showMove = false
                        if let url { onRelocate(url) }
                    }
                    .ignoresSafeArea()
                }
                .fullScreenCover(isPresented: $showCamera) {
                    CameraView(picked: $picked) { data in
                        showCamera = false
                        guard let data else { return }
                        Task {
                            await model.addPhoto(data)
                            Haptic.touch()
                            liveFocused = true
                        }
                    }
                }
                .fullScreenCover(item: $viewing) { opening in
                    if let entry = model.notebook.entry(opening.entry) {
                        let photos = entry.media.filter { $0.mime.hasPrefix("image") }
                        let index = min(opening.index, photos.count - 1)
                        PhotoViewer(entryID: entry.id, index: index, model: model)
                            .navigationTransition(.zoom(sourceID: photos[index].hash, in: zoom))
                    }
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
                        liveFocused = true
                    }
                }
                .onChange(of: liveFocused) { _, focused in
                    if !focused { storeDraft(proxy) }
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
                    case .write: liveFocused = true
                    case .photo: showCamera = true
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ULID.self) { id in
                LineView(entryID: id, model: model)
            }
        }
        .tint(Theme.accent)
    }

    /// With the keyboard up, the first tap anywhere on the page puts it away. Nothing opens
    /// until the next tap.
    private func open(_ action: () -> Void) {
        if liveFocused {
            liveFocused = false
        } else {
            action()
        }
    }

    /// Stores the live line and settles the page on it, one short motion. A line stored on an
    /// earlier day, from a photo's own moment, is shown where it landed.
    private func storeDraft(_ proxy: ScrollViewProxy) {
        var stored: ULID?
        withAnimation(Motion.settle) { stored = model.commitDraft() }
        guard let stored else { return }
        Haptic.store()
        guard filter == nil else { return }
        let day = model.notebook.entry(stored).map { DayKey($0.startedAt, calendar: model.calendar) } ?? model.today
        if day == model.today {
            withAnimation(Motion.settle) { proxy.scrollTo(model.today, anchor: .bottom) }
        } else {
            reveal(stored, on: day, proxy)
        }
    }

    /// The page goes to the day in one motion and marks the line for a moment.
    private func reveal(_ id: ULID, on day: DayKey, _ proxy: ScrollViewProxy) {
        withAnimation(Motion.settle) {
            proxy.scrollTo(day, anchor: .top)
            revealed = id
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut(duration: 0.8)) {
                if revealed == id { revealed = nil }
            }
        }
    }

    /// The day as the same markdown the folder holds.
    private func copy(day key: DayKey) {
        guard let day = model.days.first(where: { $0.key == key }) else { return }
        UIPasteboard.general.string = Projector.markdown(for: day, calendar: model.calendar)
    }

    private func copyAll() {
        UIPasteboard.general.string = model.days
            .map { Projector.markdown(for: $0, calendar: model.calendar) }
            .joined(separator: "\n")
    }
}

struct PhotoOpening: Identifiable {
    let entry: ULID
    let index: Int
    var id: String { "\(entry)-\(index)" }
}

enum Motion {
    /// One short, calm curve for everything that moves on the page.
    static let settle: Animation = .snappy(duration: 0.28, extraBounce: 0)
}

/// The date, pinned. Tap it for the calendar; hold it to copy the day as text.
/// When the page is filtered by a label, the label sits here with its x.
struct PinnedHeader: View {
    let day: DayKey
    let today: DayKey
    let calendar: Calendar
    let filter: String?
    let onTap: () -> Void
    let onClearFilter: () -> Void
    let onCopyDay: () -> Void
    let onCopyAll: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button(action: onTap) {
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
            .contextMenu {
                Button("Copy this day", systemImage: "doc.on.doc", action: onCopyDay)
                Button("Copy every day", systemImage: "doc.on.doc.fill", action: onCopyAll)
            }
            Spacer()
            if let filter {
                Button(action: onClearFilter) {
                    HStack(spacing: 6) {
                        Text("#\(filter)")
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .font(Theme.mono)
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Theme.square(28).fill(Theme.accent.opacity(0.1)))
                }
                .buttonStyle(.plain)
            } else if day != today {
                Text(relative)
                    .font(Theme.mono)
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(Theme.background.opacity(0.96))
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

/// One day and its lines.
struct DaySection: View {
    let day: Day
    @Bindable var model: NotebookModel
    let isToday: Bool
    let zoom: Namespace.ID
    let revealed: ULID?
    let onOpen: (ULID) -> Void
    let onOpenPhoto: (ULID, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !isToday {
                DayDivider(day: day.key, calendar: model.calendar)
            }
            ForEach(day.entries) { entry in
                EntryRow(
                    entry: entry,
                    model: model,
                    zoom: zoom,
                    revealed: revealed == entry.id,
                    onOpen: { onOpen(entry.id) },
                    onOpenPhoto: { index in onOpenPhoto(entry.id, index) }
                )
                .id(entry.id)
            }
        }
        .padding(.bottom, isToday ? 8 : 18)
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
/// stores the line. The camera waits at its end while it is empty.
struct LiveLine: View {
    @Bindable var model: NotebookModel
    var focused: FocusState<Bool>.Binding
    let onReturn: () -> Void
    let onCamera: () -> Void

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
                    withAnimation(Motion.settle) { model.draftKeepsPhotoMoment.toggle() }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                if !model.draftMedia.isEmpty {
                    DraftMediaRow(model: model)
                }
                TextField("", text: $model.draftText, axis: .vertical)
                    .font(Theme.serif)
                    .foregroundStyle(Theme.foreground)
                    .lineSpacing(4)
                    .lineLimit(1...8)
                    .focused(focused)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .onChange(of: model.draftText) { _, text in
                        guard text.contains("\n") else { return }
                        model.draftText = text.replacingOccurrences(of: "\n", with: " ")
                        onReturn()
                    }
            }
            if model.draftText.isEmpty {
                // The camera waits at the end of an empty line and steps aside once words
                // start, so the words get the same width as every line above.
                Button(action: onCamera) {
                    Image(systemName: "camera")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Photo")
                .transition(.opacity)
            }
        }
        .animation(Motion.settle, value: model.draftText.isEmpty)
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !focused.wrappedValue else { return }
            Haptic.touch()
            focused.wrappedValue = true
        }
    }
}

/// What has landed in the live line before its words. Hold one to take it out again.
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
                    .contextMenu {
                        Button("Take out", systemImage: "minus.circle", role: .destructive) {
                            withAnimation(Motion.settle) { model.removeDraftMedia(item) }
                        }
                    }
                }
            }
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
