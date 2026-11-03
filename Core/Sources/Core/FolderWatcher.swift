import Foundation

/// Watches the events folder and every file in it, so a line appended from another
/// device or by a reader shows up without the app being told. Calls back on the main queue.
public final class FolderWatcher {
    private let directory: URL
    private let onChange: () -> Void
    private var sources: [DispatchSourceFileSystemObject] = []

    public init(directory: URL, onChange: @escaping () -> Void) {
        self.directory = directory
        self.onChange = onChange
        rebuild()
    }

    deinit {
        sources.forEach { $0.cancel() }
    }

    private func rebuild() {
        sources.forEach { $0.cancel() }
        sources = []
        watch(directory, mask: [.write, .rename, .delete]) { [weak self] in
            self?.rebuild()
            self?.onChange()
        }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name.hasSuffix(".jsonl") {
            watch(directory.appendingPathComponent(name), mask: [.write, .extend, .rename, .delete]) { [weak self] in
                self?.onChange()
            }
        }
    }

    private func watch(_ url: URL, mask: DispatchSource.FileSystemEvent, handler: @escaping () -> Void) {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: mask, queue: .main)
        source.setEventHandler(handler: handler)
        source.setCancelHandler { close(descriptor) }
        source.resume()
        sources.append(source)
    }
}
