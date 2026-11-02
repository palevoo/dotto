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
    @State private var recorder = VoiceRecorder()
    @FocusState private var liveFocused: Bool

    private var days: [Day] {
        var days = model.days
        if days.last?.key != model.today {
            days.append(Day(key: model.today, entries: []))
        }
        return days
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(days) { day in
                        DaySection(day: day, model: model, isToday: day.key == model.today, liveFocused: $liveFocused)
                            .id(day.key)
                    }
                }
                .scrollTargetLayout()
                .padding(.bottom, 8)
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
                    onTap: { showCalendar = true },
                    onCopyDay: { copy(day: visibleDay ?? model.today) },
                    onCopyAll: { copyAll() }
                )
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                CaptureStrip(
                    recorder: recorder,
                    onCamera: { showCamera = true },
                    onHoldStart: { Task { await recorder.start() } },
                    onHoldEnd: { finishVoice() }
                )
            }
            .sheet(isPresented: $showCalendar) {
                CalendarSheet(
                    days: model.days,
                    today: model.today,
                    calendar: model.calendar,
                    home: Library.describe(model.store),
                    onPick: { key in
                        showCalendar = false
                        withAnimation { proxy.scrollTo(key, anchor: .top) }
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
                // The line grows under the keyboard; keep it in view.
                if liveFocused { followLiveLine(proxy) }
            }
            .onChange(of: model.notebook.eventCount) { _, _ in
                // A line was stored: the page settles with it instead of jumping.
                if liveFocused { followLiveLine(proxy) }
            }
        }
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

/// The date, pinned. Tap it for the calendar; hold it to copy the day as text.
struct PinnedHeader: View {
    let day: DayKey
    let today: DayKey
    let calendar: Calendar
    let onTap: () -> Void
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
            if day != today {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !isToday {
                DayDivider(day: day.key, calendar: model.calendar)
            }
            ForEach(day.entries) { entry in
                EntryRow(entry: entry, model: model)
            }
            if isToday {
                LiveLine(model: model, focused: liveFocused)
                    .id(PageAnchor.live)
            }
        }
        .padding(.bottom, isToday ? 0 : 18)
    }
}

enum PageAnchor: Hashable {
    case live
}

enum Motion {
    /// One short, calm curve for everything that moves on the page.
    static let settle: Animation = .snappy(duration: 0.28, extraBounce: 0)
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

/// The last row of today: the page itself is the composer.
/// The margin shows the current minute until the first thing lands, then keeps that moment.
/// Return stores the line. Tapping anywhere on it begins.
struct LiveLine: View {
    @Bindable var model: NotebookModel
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TimelineView(.everyMinute) { context in
                Text(Format.time(model.draftStartedAt ?? context.date, calendar: model.calendar))
                    .font(Theme.mono)
                    .foregroundStyle(model.draftStartedAt == nil ? Theme.faint : Theme.muted)
                    .frame(width: 44, alignment: .leading)
                    .monospacedDigit()
                    .padding(.top, 6)
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
        }
        .padding(.horizontal, 20)
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

/// Camera and mic. Rides above the keyboard.
struct CaptureStrip: View {
    let recorder: VoiceRecorder
    let onCamera: () -> Void
    let onHoldStart: () -> Void
    let onHoldEnd: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            if recorder.isRecording {
                HStack(spacing: 10) {
                    Theme.square(10)
                        .fill(Theme.recording)
                        .frame(width: 10, height: 10)
                    Text(Format.duration(recorder.elapsed))
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundStyle(Theme.foreground)
                        .monospacedDigit()
                    Text("Release to keep")
                        .font(Theme.mono)
                        .foregroundStyle(Theme.muted)
                }
                .padding(.leading, 16)
            } else {
                StripButton(symbol: "camera", label: "Photo", action: onCamera)
            }
            Spacer()
            HoldButton(symbol: "mic", label: "Hold to speak", onStart: onHoldStart, onEnd: onHoldEnd)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Theme.background.opacity(0.96))
        .overlay(alignment: .top) { Theme.line.frame(height: 1) }
    }
}

struct StripButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(Theme.muted)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct HoldButton: View {
    let symbol: String
    let label: String
    let onStart: () -> Void
    let onEnd: () -> Void
    @State private var holding = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 20, weight: .light))
            .foregroundStyle(holding ? Theme.recording : Theme.muted)
            .frame(width: 44, height: 44)
            .background(Theme.square(44).fill(holding ? Theme.recording.opacity(0.12) : .clear))
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
}
