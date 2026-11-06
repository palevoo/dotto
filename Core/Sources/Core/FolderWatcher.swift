import Foundation

/// Watches one path, a file or a directory, for any change, and keeps watching through a
/// replacement of the file. Calls back on the main queue.
public final class PathWatcher {
    private var source: DispatchSourceFileSystemObject?
    private let path: String
    private let onChange: () -> Void

    public init(path: String, onChange: @escaping () -> Void) {
        self.path = path
        self.onChange = onChange
        arm()
    }

    deinit {
        source?.cancel()
    }

    private func arm() {
        source?.cancel()
        source = nil
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .extend, .rename, .delete, .attrib], queue: .main)
        source.setEventHandler { [weak self] in
            self?.arm()
            self?.onChange()
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }
}

/// Watches the events folder and every file in it, so a line appended from another
/// device or through the door shows up without the app being told. Calls back on the main queue.
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
