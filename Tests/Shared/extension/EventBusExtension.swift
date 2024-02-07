@testable import CioInternalCommon
import Foundation

public extension EventStorage {
    /// Configures the event storage to use temporary directory for storing event files during testing.
    /// - Returns: The URL of the temporary directory if it was created successfully, otherwise nil.
    func configureTemporaryEventStorage() -> URL? {
        guard let eventStorageManager = self as? EventStorageManager else {
            print("EventStorage is not an instance of EventStorageManager")
            return nil
        }

        let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let uniqueDirectoryURL = temporaryDirectoryURL.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: uniqueDirectoryURL, withIntermediateDirectories: true)
            Task {
                await eventStorageManager.updateBaseDirectory(baseDirectory: uniqueDirectoryURL)
            }
        } catch {
            print("Failed to create temporary directory: \(error)")
        }
        return uniqueDirectoryURL
    }

    /// Deletes all event files in the given base directory.
    func deleteEventStorageFiles(baseDirectory: URL) {
        let fileManager = FileManager.default

        let deleteFromSearchPath: (FileManager.SearchPathDirectory) -> Void = { _ in
            // swiftlint:disable:next force_try
            let fileURLs = try! fileManager.contentsOfDirectory(
                at: baseDirectory,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
            for fileURL in fileURLs {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }
}
