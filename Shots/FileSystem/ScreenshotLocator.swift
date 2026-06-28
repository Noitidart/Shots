import Foundation

/// Finds screenshots in a directory via mdfind (kMDItemIsScreenCapture).
/// Results are sorted most recent first.
enum ScreenshotLocator {
    static func screenshotURLsSortedByCreatedAtDesc(in directoryURL: URL, olderThanHours: Int? = nil) throws -> [URL] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["-onlyin", directoryURL.path, "kMDItemIsScreenCapture == 1"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            throw NSError(domain: "ScreenshotLocator", code: 1, userInfo: [NSLocalizedDescriptionKey: "mdfind failed to launch"])
        }

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NSError(domain: "ScreenshotLocator", code: 2, userInfo: [NSLocalizedDescriptionKey: "mdfind exited with status \(process.terminationStatus)"])
        }

        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let fileManager = FileManager.default

        var urls = output
            .split(whereSeparator: \.isNewline)
            .map { URL(fileURLWithPath: String($0)) }
            .filter { $0.deletingLastPathComponent().path == directoryURL.path }
            .filter { fileManager.fileExists(atPath: $0.path) }

        if let olderThanHours {
            let cutoff = Date().addingTimeInterval(TimeInterval(-olderThanHours * 3600))
            urls = urls.filter { creationDate(for: $0) <= cutoff }
        }

        return urls.sorted { creationDate(for: $0) > creationDate(for: $1) }
    }

    private static func creationDate(for url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.creationDateKey])
        return values?.creationDate ?? .distantPast
    }
}
