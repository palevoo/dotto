import Foundation

/// Where the notebook's photos and voice notes stand with iCloud, as seen from this device.
public struct CloudState: Hashable, Sendable {
    /// Media files iCloud knows about, here or not.
    public var media = 0
    /// Written here, not yet uploaded. iCloud decides when; nothing can hurry it.
    public var leaving = 0
    /// In iCloud, not yet on this device. Asked for; on their way.
    public var arriving = 0
    /// iCloud's own words when a file would not go up or come down.
    public var trouble: String?

    public init(media: Int = 0, leaving: Int = 0, arriving: Int = 0, trouble: String? = nil) {
        self.media = media
        self.leaving = leaving
        self.arriving = arriving
        self.trouble = trouble
    }

    /// Everything iCloud knows is here, and everything here is in iCloud.
    public var settled: Bool { leaving == 0 && arriving == 0 }

    /// One file as iCloud describes it.
    public struct Item: Hashable, Sendable {
        public var isMedia: Bool
        public var uploaded: Bool
        public var downloaded: Bool
        public var trouble: String?

        public init(isMedia: Bool, uploaded: Bool, downloaded: Bool, trouble: String? = nil) {
            self.isMedia = isMedia
            self.uploaded = uploaded
            self.downloaded = downloaded
            self.trouble = trouble
        }
    }

    public init(_ items: some Sequence<Item>) {
        for item in items {
            if item.isMedia {
                media += 1
                if !item.uploaded { leaving += 1 }
                if !item.downloaded { arriving += 1 }
            }
            if trouble == nil { trouble = item.trouble }
        }
    }
}

/// Keeps a notebook folder that lives in iCloud Drive current on this device, and says
/// how far along iCloud is with it.
///
/// iCloud does not write a file's newer version to disk until something asks for it. This
/// registers interest in the folder once; iCloud then says whenever a file there has a
/// newer version, the bytes are asked for at that moment, and iCloud says again when they
/// have landed. Nothing waits and nothing polls. `FolderWatcher` sees the bytes land like
/// any other write. For a folder that is not in iCloud this is nil.
@MainActor
public final class CloudWatcher {
    private let box = Box()
    private let onChange: () -> Void

    /// Where things stand, after iCloud's first word. Nil until then.
    public private(set) var state: CloudState?

    /// The query and its observers, owned apart from the watcher so they can be stopped on
    /// the main queue whenever the watcher goes, from whatever thread that happens on.
    private final class Box: @unchecked Sendable {
        let query = NSMetadataQuery()
        var observers: [NSObjectProtocol] = []

        func tearDown() {
            DispatchQueue.main.async { [self] in
                observers.forEach { NotificationCenter.default.removeObserver($0) }
                query.stop()
            }
        }
    }

    private let mediaPath: String

    public init?(store: FileStore, onChange: @escaping () -> Void) {
        let values = try? store.root.resourceValues(forKeys: [.isUbiquitousItemKey])
        guard values?.isUbiquitousItem == true else { return nil }
        self.onChange = onChange
        mediaPath = store.mediaDirectory.path + "/"

        let query = box.query
        // The app's own container and every folder the person has let it into, which is
        // where a notebook picked in the open panel or the document picker lives.
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope, NSMetadataQueryAccessibleUbiquitousExternalDocumentsScope]
        query.predicate = NSPredicate(format: "%K BEGINSWITH %@", NSMetadataItemPathKey, store.root.path + "/")
        query.notificationBatchingInterval = 0.2

        for name in [NSNotification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            box.observers.append(NotificationCenter.default.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.handle() }
            })
        }
        query.start()
    }

    deinit {
        box.tearDown()
    }

    /// iCloud has something to say about the folder: ask for every file that is not the
    /// newest, take stock, then let the owner re-read, since some may have landed already.
    private func handle() {
        let query = box.query
        query.disableUpdates()
        defer { query.enableUpdates() }
        var items: [CloudState.Item] = []
        for case let item as NSMetadataItem in query.results {
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }
            let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            let downloaded = status == NSMetadataUbiquitousItemDownloadingStatusCurrent
            if !downloaded {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            }
            let uploadTrouble = item.value(forAttribute: NSMetadataUbiquitousItemUploadingErrorKey) as? NSError
            let downloadTrouble = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingErrorKey) as? NSError
            items.append(CloudState.Item(
                isMedia: url.path.hasPrefix(mediaPath),
                uploaded: item.value(forAttribute: NSMetadataUbiquitousItemIsUploadedKey) as? Bool ?? true,
                downloaded: downloaded,
                trouble: (uploadTrouble ?? downloadTrouble)?.localizedDescription
            ))
        }
        state = CloudState(items)
        onChange()
    }
}
