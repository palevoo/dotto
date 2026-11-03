import Foundation

/// Keeps a notebook folder that lives in iCloud Drive current on this device.
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

    public init?(store: FileStore, onChange: @escaping () -> Void) {
        let values = try? store.root.resourceValues(forKeys: [.isUbiquitousItemKey])
        guard values?.isUbiquitousItem == true else { return nil }
        self.onChange = onChange

        let query = box.query
        // The app's own container and every folder the person has let it into, which is
        // where a notebook picked in the open panel or the document picker lives.
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope, NSMetadataQueryAccessibleUbiquitousExternalDocumentsScope]
        query.predicate = NSPredicate(format: "%K BEGINSWITH %@", NSMetadataItemPathKey, store.eventsDirectory.path)
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
    /// newest, then let the owner re-read, since some may have landed already.
    private func handle() {
        let query = box.query
        query.disableUpdates()
        defer { query.enableUpdates() }
        for case let item as NSMetadataItem in query.results {
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
                  let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String,
                  status != NSMetadataUbiquitousItemDownloadingStatusCurrent else { continue }
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
        onChange()
    }
}
