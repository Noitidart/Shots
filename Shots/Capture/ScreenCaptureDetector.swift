import Foundation

// MARK: - Screen Capture Detector

/// Watches a folder for new screenshots appearing, with bounded/cancelable retry.
///
/// When a DirectoryWatcher event fires (a file changed in the folder), the detector
/// scans for screenshots whose `creationDate` is newer than the last seen date. If
/// found, it calls `onNewScreenshot` with the most recent new URL. If not found, it
/// retries every 50 ms up to a 5-second hard cap. "Not found" can mean two things:
/// mdfind (Spotlight) indexing lags behind the file appearing on disk (typically
/// 100-500 ms), or the watcher event was triggered by a non-capture file change
/// (e.g. .DS_Store, a temp file). The 5-second timeout lets us give up and conclude
/// it wasn't a screenshot.
///
/// We track creation date because:
/// - A rename via the panel triggers a watcher event; `moveItem` preserves the inode so
///   `creationDate` is unchanged and the renamed file is still ignored.
/// - A manually dropped old screenshot won't trigger, as long as a newer one already
///   existed in the folder. If the folder had no prior screenshots, the dropped file
///   becomes the newest and triggers — an accepted edge case with no suppression yet.
@MainActor
final class ScreenCaptureDetector {
    private var watcher: DirectoryWatcher?
    private var watchedFolderURL: URL?
    private var lastSeenCaptureDate: Date = .distantPast
    private var retryWorkItem: DispatchWorkItem?
    private var retryStartTime: Date?

    var onNewScreenshot: ((URL) -> Void)?

    // MARK: - Lifecycle

    /// Baselines the newest existing screenshot's creation date (so existing
    /// screenshots don't trigger) and starts watching.
    ///
    /// Throws if the DirectoryWatcher can't open the folder (permission denied,
    /// doesn't exist, etc.).
    func startWatching(folder: URL) throws {
        stop()

        // Baseline: record the newest existing screenshot's creation date.
        // Everything older than this is already known.
        let existing = (try? ScreenshotLocator.screenshotURLsSortedByCreatedAtDesc(in: folder)) ?? []
        lastSeenCaptureDate = existing.first.flatMap { Self.creationDate(for: $0) } ?? .distantPast
        watchedFolderURL = folder
        retryStartTime = nil

        watcher = try DirectoryWatcher(directoryURL: folder) { [weak self] in
            guard let self else { return }
            self.stopRetry()
            self.retryStartTime = Date()
            self.scan()
        }
        watcher?.start()
    }

    func stop() {
        watcher = nil
        stopRetry()
        watchedFolderURL = nil
        lastSeenCaptureDate = .distantPast
    }

    // MARK: - Scan

    private func scan() {
        guard let folder = watchedFolderURL else { return }

        let all = (try? ScreenshotLocator.screenshotURLsSortedByCreatedAtDesc(in: folder)) ?? []

        // `all` is sorted descending by creation date, so the first element is the newest.
        if let newest = all.first, Self.creationDate(for: newest) > lastSeenCaptureDate {
            lastSeenCaptureDate = Self.creationDate(for: newest)
            stopRetry()
            onNewScreenshot?(newest)
            return
        }

        scheduleRetry()
    }

    // MARK: - Retry

    private func scheduleRetry() {
        if retryWorkItem != nil { return }

        if retryStartTime == nil {
            retryStartTime = Date()
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.retryWorkItem = nil

            if let start = self.retryStartTime,
               Self.elapsedMilliseconds(since: start) >= 5_000 {
                self.stopRetry()
                return
            }

            self.scan()
        }
        retryWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    private func stopRetry() {
        retryWorkItem?.cancel()
        retryWorkItem = nil
        retryStartTime = nil
    }

    // MARK: - Helpers

    private static func creationDate(for url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.creationDateKey])
        return values?.creationDate ?? .distantPast
    }

    private static func elapsedMilliseconds(since startDate: Date) -> Int {
        Int((Date().timeIntervalSince(startDate) * 1_000).rounded())
    }
}
