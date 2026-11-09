import Core
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Margin in the share sheet: what was shared, a place for a word or two, Return keeps it
/// as a line on today. Nothing to pick, nothing to file.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let model = ShareModel(context: extensionContext)
        let host = UIHostingController(rootView: ShareView(model: model))
        addChild(host)
        view.addSubview(host.view)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.didMove(toParent: self)
        Task { await model.load() }
    }
}

/// What came through the sheet, and the words added to it.
@MainActor
@Observable
final class ShareModel {
    struct Shot: Identifiable {
        let hash: String
        let jpeg: Data
        let thumbnail: UIImage
        let width: Int
        let height: Int
        var id: String { hash }
    }

    var words = ""
    private(set) var sharedText: String?
    private(set) var sharedURL: URL?
    private(set) var photos: [Shot] = []
    private(set) var loading = true
    private(set) var kept = false
    let ready = Inbox.owner != nil && Inbox.device != nil

    private let context: NSExtensionContext?

    init(context: NSExtensionContext?) {
        self.context = context
    }

    func load() async {
        defer { loading = false }
        for item in context?.inputItems as? [NSExtensionItem] ?? [] {
            if sharedText == nil, let text = item.attributedContentText?.string.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                sharedText = text
            }
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    if let data = await imageData(from: provider), let processed = await Photo.process(data) {
                        guard let thumbnail = UIImage(data: processed.thumbnail) else { continue }
                        photos.append(Shot(hash: FileStore.hash(of: processed.jpeg), jpeg: processed.jpeg,
                                            thumbnail: thumbnail, width: processed.width, height: processed.height))
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL, !url.isFileURL {
                        sharedURL = url
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let text = await plainText(from: provider), !text.isEmpty {
                        sharedText = text
                    }
                }
            }
        }
    }

    private func imageData(from provider: NSItemProvider) async -> Data? {
        guard let item = try? await provider.loadItem(forTypeIdentifier: UTType.image.identifier) else { return nil }
        if let url = item as? URL { return try? Data(contentsOf: url) }
        if let data = item as? Data { return data }
        if let image = item as? UIImage { return image.jpegData(compressionQuality: 0.92) }
        return nil
    }

    private func plainText(from provider: NSItemProvider) async -> String? {
        guard let item = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) else { return nil }
        if let text = item as? String { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let data = item as? Data { return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let rich = item as? NSAttributedString { return rich.string.trimmingCharacters(in: .whitespacesAndNewlines) }
        return nil
    }

    /// The line as it will read: your words first, then what was shared.
    var lineText: String {
        var parts = [words.trimmingCharacters(in: .whitespacesAndNewlines)]
        if let sharedText { parts.append(sharedText) }
        if let sharedURL { parts.append(sharedURL.absoluteString) }
        return parts.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    var hasSomething: Bool { !lineText.isEmpty || !photos.isEmpty }

    func keep() {
        guard ready, hasSomething, !kept, let owner = Inbox.owner, let device = Inbox.device else { return }
        kept = true
        let now = Date()
        let generator = ULIDGenerator()
        let id = generator.next(at: now)
        var events = [
            Event(id: id, author: owner, device: device, at: now,
                  payload: .entryCreate(.init(entry: id, text: lineText, startedAt: now))),
        ]
        for photo in photos {
            events.append(Event(id: generator.next(at: now), author: owner, device: device, at: now,
                                payload: .mediaAttach(.init(entry: id, hash: photo.hash, mime: "image/jpeg",
                                                            width: photo.width, height: photo.height))))
        }
        do {
            try Inbox.keep(events, media: photos.map { ($0.hash, $0.jpeg) })
            context?.completeRequest(returningItems: [], completionHandler: nil)
        } catch {
            kept = false
            NSLog("share failed: \(error)")
        }
    }

    func cancel() {
        context?.cancelRequest(withError: NSError(domain: "social.interface.notebook.share", code: 0))
    }
}

struct ShareView: View {
    @Bindable var model: ShareModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: model.cancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                Spacer()
                if model.ready {
                    Button(action: model.keep) {
                        Text("Keep")
                            .font(Theme.mono)
                            .foregroundStyle(model.hasSomething ? Theme.accent : Theme.faint)
                            .frame(height: 44)
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.hasSomething || model.loading)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)

            if model.ready {
                HStack(alignment: .top, spacing: 12) {
                    Text(Self.time(Date()))
                        .font(Theme.mono)
                        .foregroundStyle(Theme.muted)
                        .monospacedDigit()
                        .frame(width: 44, alignment: .leading)
                        .padding(.top, 6)
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("", text: $model.words, axis: .vertical)
                            .font(Theme.serif)
                            .foregroundStyle(Theme.foreground)
                            .lineSpacing(4)
                            .lineLimit(1...6)
                            .focused($focused)
                            .textInputAutocapitalization(.sentences)
                            .submitLabel(.done)
                            .onChange(of: model.words) { _, text in
                                guard text.contains("\n") else { return }
                                model.words = text.replacingOccurrences(of: "\n", with: " ")
                                model.keep()
                            }
                        if !model.photos.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(model.photos) { photo in
                                        Image(uiImage: photo.thumbnail)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 96, height: 96)
                                            .clipShape(Theme.square(96))
                                            .overlay(Theme.square(96).strokeBorder(Theme.line, lineWidth: 1))
                                    }
                                }
                            }
                            .scrollClipDisabled()
                        }
                        if let text = model.sharedText {
                            Text(text)
                                .font(Theme.serif)
                                .foregroundStyle(Theme.foreground)
                                .lineSpacing(4)
                                .lineLimit(8)
                        }
                        if let url = model.sharedURL {
                            Text(url.absoluteString)
                                .font(Theme.mono)
                                .foregroundStyle(Theme.muted)
                                .lineLimit(2)
                                .truncationMode(.middle)
                        }
                        if model.loading && model.photos.isEmpty && model.sharedText == nil && model.sharedURL == nil {
                            Text("…")
                                .font(Theme.mono)
                                .foregroundStyle(Theme.faint)
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                .onTapGesture { focused = true }
            } else {
                Text("Open dotto once on this phone, then share.")
                    .font(Theme.serifSmall)
                    .foregroundStyle(Theme.muted)
                    .padding(20)
            }
            Spacer(minLength: 0)
        }
        .background(Theme.background.ignoresSafeArea())
        .onAppear { focused = model.ready }
    }

    private static func time(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}
