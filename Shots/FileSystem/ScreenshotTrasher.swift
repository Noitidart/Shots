import Foundation

// MARK: - Trash Scope

/// A scope for trashing screenshots — either all of them, or only those older than a threshold.
enum ScreenshotTrashScope {
    case all
    case old(minimumAgeInHours: Int, ageDescription: String)

    var minimumAgeInHours: Int? {
        switch self {
        case .all: return nil
        case .old(let hours, _): return hours
        }
    }

    func emptyMessage(in folderName: String) -> String {
        switch self {
        case .all:
            return "No screenshots to trash in \(folderName)."
        case .old(_, let ageDescription):
            return "No screenshots older than \(ageDescription) in \(folderName)."
        }
    }

    func successMessage(count: Int, in folderName: String) -> String {
        let noun = count == 1 ? "screenshot" : "screenshots"
        switch self {
        case .all:
            return "Trashed \(count) \(noun) from \(folderName)."
        case .old(_, let ageDescription):
            return "Trashed \(count) \(noun) older than \(ageDescription) from \(folderName)."
        }
    }
}

// MARK: - Screenshot Trasher

enum ScreenshotTrasher {
    static func trashScreenshots(in folder: URL, scope: ScreenshotTrashScope,
                                 completion: @escaping (Result<Int, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let candidates = try ScreenshotLocator.screenshotURLsSortedByCreatedAtDesc(
                    in: folder,
                    olderThanHours: scope.minimumAgeInHours
                )

                if candidates.isEmpty {
                    DispatchQueue.main.async { completion(.success(0)) }
                    return
                }

                let fileManager = FileManager.default
                for url in candidates {
                    do {
                        try fileManager.trashItem(at: url, resultingItemURL: nil)
                    } catch {
                        DispatchQueue.main.async {
                            completion(.failure(NSError(domain: "ScreenshotTrasher", code: 1, userInfo: [
                                NSLocalizedDescriptionKey: "Could not move to Trash: \(url.lastPathComponent)"
                            ])))
                        }
                        return
                    }
                }

                DispatchQueue.main.async { completion(.success(candidates.count)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }
}
