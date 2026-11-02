import Core
import SwiftUI
import UIKit

/// The page. Days scroll up into the past; today ends in the live line; the date is pinned above.
struct PageView: View {
    @Bindable var model: NotebookModel
    let onRelocate: (URL) -> Void
    @State private var visibleDay: DayKey?
    @State private var showCalendar = false
    @State private var showMove = false
    @State private var showCamera = false
    @State private var filter: String?
    @State private var recorder = VoiceRecorder()
    @FocusState private var liveFocused: Bool

    private var days: [Day] {
        if let filter {
            return model.notebook.days(labelled: filter, calendar: model.calendar)
        }
        var days = model.days
        if days.last?.key != model.today {
            days.append(Day(key: model.today, entries: []))
        }
        return days
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(days) { day in
                            DaySection(
                                day: day,
                                model: model,
                                isToday: filter == nil && day.key == model.today,
                                liveFocused: $liveFocused,
                                recorder: recorder,
                                onCamera: { showCamera = true },
                                onHoldStart: { Task { await recorder.start() } },
                                onHoldEnd: { finishVoice() }
                            )
                            .id(day.key)
                        }
                        if filter != nil, days.isEmpty {
                            Text("Nothing filed here yet.")
                                .font(Theme.serifSmall)
                                .foregroundStyle(Theme.muted)
                                .padding(20)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.bottom, 24)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // A tap on bare page puts the keyboard away. Lines keep their own taps.
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
                .scrollPosition(id: $visibleDay, anchor: .top)
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .background(Theme.background.ignoresSafeArea())
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
                    .presentationDetents([.medium, .large])
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
                    CameraView { data in
                        showCamera = false
                        guard let data else { return }
                        Task {
                            await model.addPhoto(data)
                            Haptic.touch()
                            liveFocused = true
                        }
                    }
                }
                .onChange(of: liveFocused) { _, focused in
                    if focused {
                        followLiveLine(proxy)
                    } else {
                        var stored: ULID?
                        withAnimation(Motion.settle) { stored = model.commitDraft() }
                        if stored != nil { Haptic.store() }
                    }
                }
                .onChange(of: model.draftText) { _, _ in
                    if liveFocused { followLiveLine(proxy) }
                }
                .onChange(of: model.notebook.eventCount) { _, _ in
                    if liveFocused { followLiveLine(proxy) }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ULID.self) { id in
                LineView(entryID: id, model: model)
            }
        }
        .tint(Theme.accent)
    }

    private func followLiveLine(_ proxy: ScrollViewProxy) {
        withAnimation(Motion.settle) { proxy.scrollTo(PageAnchor.live, anchor: .bottom) }
    }

    private func finishVoice() {
        guard let take = recorder.stop() else { return }
        Task {
            let transcript = await Transcriber.transcribe(take.fileURL)
            model.addVoice(fileURL: take.fileURL, duration: take.duration, transcript: transcript, startedAt: take.startedAt)
            Haptic.touch()
            liveFocused = true
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

enum PageAnchor: Hashable {
    case live
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

/// One day: its entries and, for today, the live line.
struct DaySection: View {
    let day: Day
    @Bindable var model: NotebookModel
    let isToday: Bool
    var liveFocused: FocusState<Bool>.Binding
    let recorder: VoiceRecorder
    let onCamera: () -> Void
    let onHoldStart: () -> Void
    let onHoldEnd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !isToday {
                DayDivider(day: day.key, calendar: model.calendar)
            }
            ForEach(day.entries) { entry in
                EntryRow(entry: entry, model: model)
            }
            if isToday {
                LiveLine(
                    model: model,
                    focused: liveFocused,
                    recorder: recorder,
                    onCamera: onCamera,
                    onHoldStart: onHoldStart,
                    onHoldEnd: onHoldEnd
                )
                .id(PageAnchor.live)
            }
        }
        .padding(.bottom, isToday ? 0 : 18)
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

/// The last row of today: the page itself is the composer, and everything that can land
/// on it lands here. The margin breathes the current minute until the first thing arrives,
/// then keeps that moment. Return stores the line. Camera and mic sit at its end.
struct LiveLine: View {
    @Bindable var model: NotebookModel
    var focused: FocusState<Bool>.Binding
    let recorder: VoiceRecorder
    let onCamera: () -> Void
    let onHoldStart: () -> Void
    let onHoldEnd: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TimelineView(.everyMinute) { context in
                Text(Format.time(model.draftStartedAt ?? context.date, calendar: model.calendar))
                    .font(Theme.mono)
                    .foregroundStyle(model.draftStartedAt == nil ? Theme.faint : Theme.muted)
                    .frame(width: 44, alignment: .leading)
                    .monospacedDigit()
                    .padding(.top, 6)
                    .phaseAnimator([1.0, 0.4]) { view, phase in
                        view.opacity(model.draftStartedAt == nil ? phase : 1)
                    } animation: { _ in
                        .easeInOut(duration: 1.8)
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
                    .focused(focused)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .onChange(of: model.draftText) { _, text in
                        guard text.contains("\n") else { return }
                        model.draftText = text.replacingOccurrences(of: "\n", with: " ")
                        var stored: ULID?
                        withAnimation(Motion.settle) { stored = model.commitDraft() }
                        if stored != nil { Haptic.store() }
                    }
            }
            if recorder.isRecording {
                HStack(spacing: 8) {
                    Theme.square(10)
                        .fill(Theme.recording)
                        .frame(width: 10, height: 10)
                    Text(Format.duration(recorder.elapsed))
                        .font(Theme.mono)
                        .foregroundStyle(Theme.foreground)
                        .monospacedDigit()
                }
                .frame(height: 36)
                .padding(.trailing, 4)
            } else {
                HStack(spacing: 0) {
                    Button(action: onCamera) {
                        Image(systemName: "camera")
                            .font(.system(size: 17, weight: .light))
                            .foregroundStyle(Theme.faint)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Photo")
                    HoldButton(symbol: "mic", label: "Hold to speak", size: 36, onStart: onHoldStart, onEnd: onHoldEnd)
                }
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 8)
        .padding(.vertical, 10)
        .frame(minHeight: 140, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !focused.wrappedValue else { return }
            Haptic.touch()
            focused.wrappedValue = true
        }
    }
}

/// What has landed in the live line before its words.
struct DraftMediaRow: View {
    let model: NotebookModel

    var body: some View {
        HStack(spacing: 10) {
            ForEach(model.draftMedia) { item in
                if item.mime.hasPrefix("image") {
                    ThumbView(hash: item.hash, original: model.mediaURL(item), side: 120)
                } else {
                    VoiceChip(hash: item.hash, duration: item.duration ?? 0, url: model.mediaURL(item))
                }
            }
        }
    }
}

struct HoldButton: View {
    let symbol: String
    let label: String
    var size: CGFloat = 44
    let onStart: () -> Void
    let onEnd: () -> Void
    @State private var holding = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size > 40 ? 20 : 17, weight: .light))
            .foregroundStyle(holding ? Theme.recording : Theme.faint)
            .frame(width: size, height: size)
            .background(Theme.square(size).fill(holding ? Theme.recording.opacity(0.12) : .clear))
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.25, maximumDistance: 60) {
            } onPressingChanged: { pressing in
                if pressing {
                    holding = true
                    Haptic.touch()
                    onStart()
                } else if holding {
                    holding = false
                    onEnd()
                }
            }
            .accessibilityLabel(label)
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

    static func day(_ key: DayKey, calendar: Calendar, withYear: Bool = true) -> String {
        guard let date = key.date(in: calendar) else { return key.description }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale
        formatter.setLocalizedDateFormatFromTemplate(withYear ? "EEEE d MMMM yyyy" : "EEEE d MMMM")
        return formatter.string(from: date)
    }
}
