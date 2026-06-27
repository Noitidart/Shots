import Foundation

final class DirectoryWatcher {
    private let onChange: @MainActor () -> Void
    private let fileDescriptor: CInt
    private let source: DispatchSourceFileSystemObject

    init(directoryURL: URL, onChange: @escaping @MainActor () -> Void) throws {
        // .write is the only mask we need. For a directory fd, .write fires when the
        // directory's entry list changes (file added or removed):
        // - Screenshot folder: a new screenshot lands → entry added → .write fires.
        //   Deletions also fire .write, but the caller's scan finds nothing new → no-op.
        // - ~/Library/Preferences: plist writes are atomic (temp file + rename) →
        //   entry list changes → .write fires. The caller's change-token gate (inside
        //   onChange) filters out unrelated preference writes.
        let descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }

        self.onChange = onChange
        self.fileDescriptor = descriptor
        self.source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: .write,
            queue: .main
        )

        self.source.setEventHandler { [weak self] in
            guard let self else { return }
            Task { @MainActor in self.onChange() }
        }
        self.source.setCancelHandler { [descriptor] in close(descriptor) }
    }

    func start() {
        source.resume()
    }

    deinit {
        source.cancel()
    }
}
