import Foundation

public extension FileManager {
    func moveFilesAndDirectories(from sourceUrl: URL, to destinationUrl: URL) throws {
        let fileURLs = try contentsOfDirectory(at: sourceUrl, includingPropertiesForKeys: nil)

        for fileURL in fileURLs {
            let destinationURL = destinationUrl.appendingPathComponent(fileURL.lastPathComponent)
            try moveItem(at: fileURL, to: destinationURL)
        }
    }
}
