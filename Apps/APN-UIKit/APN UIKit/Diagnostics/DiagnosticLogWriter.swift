import Darwin
import Foundation

/// Appends NDJSON records to a file on disk.
///
/// NDJSON rather than a JSON array specifically because it is append-safe and
/// truncation-tolerant: a process killed mid-write loses one line, not the file. Losing the file
/// is losing the drive.
final class DiagnosticLogWriter: @unchecked Sendable {
    /// Two weeks covers a test cycle; a drive is single-digit megabytes.
    private static let maxFiles = 14
    private static let maxTotalBytes = 100 * 1024 * 1024

    private static let filePrefix = "cio-diag-"
    private static let fileSuffix = ".ndjson"

    private let directory: URL
    private let lock = NSLock()

    private var fd: Int32 = -1
    private var header = ""
    private var currentPath = ""
    /// Counts records since the last check that the file we hold open still exists.
    private var writesSinceExistenceCheck = 0
    /// One `access(2)` every this many records — about 0.4% overhead, against silently writing a
    /// whole drive into a deleted inode.
    private static let existenceCheckInterval = 256
    /// Wall-clock instant at which today's file stops being today's file. Compared against on
    /// every record so that rotation costs an inequality rather than a date format.
    private var rolloverAt: TimeInterval = 0

    private static let dayFormatter = DiagnosticLocked<DateFormatter>({
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter
    }())

    init(directory: URL) {
        self.directory = directory
    }

    // MARK: - Opening

    func open(header: String) {
        lock.lock()
        defer { lock.unlock() }
        self.header = header
        prune()
        openCurrentFile(now: Date())
    }

    /// Rotation is **per day, not per launch.** A phone woken repeatedly in the background
    /// relaunches the process many times over a drive, and per-launch rotation would shatter one
    /// drive across a dozen files that then have to be reassembled in the right order. Process
    /// deaths stay perfectly visible as `session.start` records *inside* the file.
    private func openCurrentFile(now: Date) {
        closeCurrentFile()

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                // Without this, writes fail silently while the device is locked — which is exactly
                // when a background geofence wake runs. Matches the protection class the SDK's own
                // GeofenceStorage uses.
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
        } catch {
            return
        }

        let url = fileURL(for: now)
        let isNew = !FileManager.default.fileExists(atPath: url.path)

        // O_APPEND makes each write atomic with respect to other writers, so interleaved records
        // stay whole lines even if the host app ever runs the SDK in a second process.
        fd = Darwin.open(url.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        guard fd >= 0 else { return }

        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )

        currentPath = url.path
        rolloverAt = DiagnosticLogWriter.startOfNextDay(after: now)
        writesSinceExistenceCheck = 0

        if isNew, !header.isEmpty {
            write(header)
        }
    }

    private func closeCurrentFile() {
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
    }

    // MARK: - Appending

    func append(_ line: String) {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        if now.timeIntervalSince1970 >= rolloverAt {
            openCurrentFile(now: now)
        } else if needsExistenceCheck(), !FileManager.default.fileExists(atPath: currentPath) {
            // The file was unlinked while we held it open — a person clearing logs from the Files
            // app, Finder, or a script. Writes to the open descriptor still "succeed" and go
            // nowhere, so without this the rest of the drive is lost in silence.
            openCurrentFile(now: now)
        }
        write(line)
    }

    private func needsExistenceCheck() -> Bool {
        writesSinceExistenceCheck += 1
        guard writesSinceExistenceCheck >= DiagnosticLogWriter.existenceCheckInterval else {
            return false
        }
        writesSinceExistenceCheck = 0
        return true
    }

    /// One unbuffered `write(2)` per record, so a record that has returned is already in the file
    /// and survives the process being killed the instant afterwards — which is the normal way a
    /// background wake ends.
    ///
    /// Deliberately no `fsync`: that would only add durability across a kernel panic or power
    /// loss, at the cost of a flash write per log line for hours at a time.
    private func write(_ line: String) {
        guard fd >= 0 else { return }
        var bytes = Array(line.utf8)
        bytes.append(UInt8(ascii: "\n"))

        bytes.withUnsafeBufferPointer { buffer in
            guard var pointer = buffer.baseAddress else { return }
            var remaining = buffer.count
            while remaining > 0 {
                let written = Darwin.write(fd, pointer, remaining)
                if written <= 0 {
                    // EINTR is worth retrying; anything else means this record is lost. Dropping
                    // it is correct — the alternative is a spin that burns battery in the
                    // background for a diagnostics file.
                    if written < 0, errno == EINTR { continue }
                    return
                }
                pointer += written
                remaining -= written
            }
        }
    }

    // MARK: - Retention

    /// Files on disk, newest first.
    func files() -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return contents
            .filter { $0.lastPathComponent.hasPrefix(DiagnosticLogWriter.filePrefix) }
            // Names are `cio-diag-YYYY-MM-DD`, so lexical order is chronological order and no
            // filesystem date has to be trusted.
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Enforces the retention policy by evicting the **oldest** files.
    ///
    /// Never clears the directory on launch. A drive that ended with the phone dying, or an
    /// engineer who forgot to pull the file before the next test, must still find yesterday's data
    /// where they left it.
    private func prune() {
        let existing = files()
        guard !existing.isEmpty else { return }

        var kept: [URL] = []
        var total = 0

        for url in existing {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let withinCount = kept.count < DiagnosticLogWriter.maxFiles
            let withinSize = total + size <= DiagnosticLogWriter.maxTotalBytes
            // The newest file is always kept, however large it is — it may be the drive that has
            // not been pulled off the device yet.
            if kept.isEmpty || (withinCount && withinSize) {
                kept.append(url)
                total += size
            } else {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: - Paths

    private func fileURL(for date: Date) -> URL {
        let day = DiagnosticLogWriter.dayFormatter.withValue { $0.string(from: date) }
        return directory.appendingPathComponent(
            "\(DiagnosticLogWriter.filePrefix)\(day)\(DiagnosticLogWriter.fileSuffix)",
            isDirectory: false
        )
    }

    private static func startOfNextDay(after date: Date) -> TimeInterval {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        guard let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))
        else {
            // Falling back to a fixed 24 hours keeps the file rotating rather than growing without
            // bound, on the calendars where the above can fail.
            return date.timeIntervalSince1970 + 86400
        }
        return next.timeIntervalSince1970
    }
}
