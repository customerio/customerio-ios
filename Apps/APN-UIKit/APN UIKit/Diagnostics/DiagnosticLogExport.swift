import Foundation
import UIKit

/// Getting the files off the phone.
enum DiagnosticLogExport {
    /// Presents a share sheet for the whole diagnostics directory, zipped.
    @MainActor
    static func presentShareSheet(from viewController: UIViewController, sourceView: UIView?) {
        let files = DiagnosticLog.shared.sessionFiles()
        guard !files.isEmpty else {
            present(message: "No diagnostic logs on disk yet.", from: viewController)
            return
        }

        guard let archive = makeArchive() else {
            present(message: "Could not package the diagnostic logs.", from: viewController)
            return
        }

        let activity = UIActivityViewController(activityItems: [archive], applicationActivities: nil)
        // Required on iPad, where a share sheet without an anchor is a crash rather than a
        // fallback.
        activity.popoverPresentationController?.sourceView = sourceView ?? viewController.view
        activity.popoverPresentationController?.sourceRect = (sourceView ?? viewController.view).bounds
        viewController.present(activity, animated: true)
    }

    /// Zips the diagnostics directory using `NSFileCoordinator`'s `.forUploading` option, which
    /// produces an archive of a directory without pulling in a compression dependency.
    private static func makeArchive() -> URL? {
        var coordinatorError: NSError?
        var result: URL?

        NSFileCoordinator().coordinate(
            readingItemAt: DiagnosticLog.directory,
            options: [.forUploading],
            error: &coordinatorError
        ) { zippedURL in
            // The coordinated URL is only valid inside this block, so it has to be copied out to a
            // location that survives it.
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("cio-diagnostics-\(Int(Date().timeIntervalSince1970)).zip")
            try? FileManager.default.removeItem(at: destination)
            do {
                try FileManager.default.copyItem(at: zippedURL, to: destination)
                result = destination
            } catch {
                result = nil
            }
        }

        return coordinatorError == nil ? result : nil
    }

    /// A one-line summary for the Location Test screen, so it is obvious before setting off
    /// whether the sink is actually capturing anything.
    static func statusSummary() -> String {
        let files = DiagnosticLog.shared.sessionFiles()
        guard let newest = files.first else {
            return "No log files yet."
        }
        let size = (try? newest.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let formatted = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        return "\(files.count) file(s) · newest \(newest.lastPathComponent) (\(formatted))"
    }

    @MainActor
    private static func present(message: String, from viewController: UIViewController) {
        let alert = UIAlertController(title: "Diagnostic logs", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        viewController.present(alert, animated: true)
    }
}
