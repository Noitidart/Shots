import Foundation

// MARK: - Rename Failure

enum RenameFailure: LocalizedError {
    case emptyName
    case invalidCharacters(String)   // the offending characters
    case destinationAlreadyExists

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Enter a file name before pressing Return."
        case .invalidCharacters(let chars):
            return "File names cannot contain \(chars)."
        case .destinationAlreadyExists:
            return "A file with that name already exists in the screenshot folder."
        }
    }
}

// MARK: - File System

enum FileSystem {

    // MARK: - Validation

    static func validateName(_ proposed: String) throws -> String {
        let trimmed = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RenameFailure.emptyName }

        let invalid = ["/", ":"]
        if let bad = invalid.first(where: { trimmed.contains($0) }) {
            throw RenameFailure.invalidCharacters("\"\(bad)\"")
        }

        return trimmed
    }

    // MARK: - URL building

    static func targetURL(from originalURL: URL, baseName: String) -> URL {
        // Preserves the original file extension (PNG, JPG, etc.)
        originalURL
            .deletingLastPathComponent()
            .appendingPathComponent(baseName)
            .appendingPathExtension(originalURL.pathExtension)
    }

    static func autoSuffixedURL(from originalURL: URL, baseName: String) -> URL {
        let dir = originalURL.deletingLastPathComponent()
        var suffix = 2

        while true {
            let candidate = dir
                .appendingPathComponent("\(baseName) \(suffix)")
                .appendingPathExtension(originalURL.pathExtension)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            suffix += 1
        }
    }

    // MARK: - Rename with retry

    /// Renames a file, retrying transient filesystem errors (up to 50 × 100 ms).
    /// Transient errors (file not settled yet): ENOENT, EBUSY, EAGAIN,
    ///   NSFileNoSuchFileError, NSFileWriteUnknownError.
    /// Permanent errors (won't fix themselves): permission denied, already exists,
    ///   empty name, invalid characters.
    static func renameSafely(from originalURL: URL, to targetURL: URL) async throws {
        do {
            try performRename(from: originalURL, to: targetURL)
            return
        } catch {
            guard shouldRetry(error) else { throw error }

            var latestError: Error = error
            for _ in 0..<50 {
                try await Task.sleep(for: .milliseconds(100))
                do {
                    try performRename(from: originalURL, to: targetURL)
                    return
                } catch {
                    latestError = error
                    guard shouldRetry(error) else { throw error }
                }
            }
            throw latestError
        }
    }

    private static func performRename(from originalURL: URL, to targetURL: URL) throws {
        if FileManager.default.fileExists(atPath: targetURL.path) {
            throw RenameFailure.destinationAlreadyExists
        }
        try FileManager.default.moveItem(at: originalURL, to: targetURL)
    }

    private static func shouldRetry(_ error: Error) -> Bool {
        if let failure = error as? RenameFailure {
            switch failure {
            case .emptyName, .invalidCharacters, .destinationAlreadyExists:
                return false
            }
        }

        let ns = error as NSError

        if ns.domain == NSCocoaErrorDomain {
            switch ns.code {
            case NSFileNoSuchFileError, NSFileWriteUnknownError:
                return true
            case NSFileWriteNoPermissionError, NSFileWriteFileExistsError:
                return false
            default:
                break
            }
        }

        if ns.domain == NSPOSIXErrorDomain {
            switch ns.code {
            case Int(ENOENT), Int(EBUSY), Int(EAGAIN):
                return true
            case Int(EACCES), Int(EPERM):
                return false
            default:
                break
            }
        }

        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            return shouldRetry(underlying)
        }

        return false
    }
}
