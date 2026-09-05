import CioInternalCommon
import Foundation
import UIKit

/// Field-drive diagnostics sink.
enum DiagnosticLogSchema {
    /// Bumped only when a field is removed, renamed, or changes meaning. Adding an optional
    /// field is not a bump — parsers ignore unknown fields.
    /// 2: `dev` is no longer on every record — it appears when the snapshot changes, on the first
    /// record of a file, and on a heartbeat. A record without `dev` means "unchanged since the last
    /// one that carried it". The header also gained `filter`.
    static let version = 2
}

final class DiagnosticLog: @unchecked Sendable {
    static let shared = DiagnosticLog()

    /// Same delimiter the SDK's geofence tail uses. The app's own records follow the same
    /// contract so one parser reads the whole file — inline `key=value` in the prose would be
    /// invisible to it.
    static let delimiter = " || "

    /// Who produced the record: the SDK's logger, or the sample app itself.
    enum Source: String {
        case sdk
        case app
    }

    private let lock = NSRecursiveLock()
    private let writer: DiagnosticLogWriter
    private let deviceState = DiagnosticDeviceState()
    /// The SDK's own console logger, reached through the shared graph so forwarded records land
    /// in Xcode and Console.app byte-identically to how they would without a dispatcher installed.
    private let systemLogger: SystemLogger = CioInternalCommon.DIGraphShared.shared.systemLogger

    private var seq = 0
    private var started = false

    /// The device-state snapshot was on every record and cost 19-31% of every file. It changes
    /// rarely — 947 surviving records in the sample corpus carried only 37 distinct snapshots — so
    /// it now rides only when it changes, plus a heartbeat so a reader starting mid-file resyncs.
    /// Absence means "unchanged since the last record that carried it".
    private var lastDevJSON: String?
    private var lastDevAt: Date?
    private var recordsSinceDev = 0
    /// Wall clock, not the monotonic reading: the latter restarts per process and a file spans
    /// several.
    private let devHeartbeat: TimeInterval = 120
    private let devHeartbeatRecords = 200
    /// Guards against a record emitted from inside the sink itself recursing forever.
    private var isEmitting = false

    private let pid = ProcessInfo.processInfo.processIdentifier
    /// Monotonic reading taken when the sink starts. `start()` is the first statement in
    /// `didFinishLaunchingWithOptions`, so this is within milliseconds of process start.
    private var startMono: UInt64 = 0

    private init() {
        self.writer = DiagnosticLogWriter(directory: DiagnosticLog.directory)
    }

    // MARK: - Location on disk

    /// `Documents/`, never `Caches/` — the OS can purge Caches under memory pressure, and doing
    /// so mid-drive would silently discard the drive.
    static let directory: URL = {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("cio-diagnostics", isDirectory: true)
    }()

    // MARK: - Lifecycle

    /// Install the sink. Call this as the **first** statement of
    /// `application(_:didFinishLaunchingWithOptions:)`.
    @MainActor
    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard !started else { return }
        started = true
        startMono = DiagnosticClock.monotonicNanos()

        // The SDK's diagnostic tail is enabled by the CIOGeofenceDiagnostics Info.plist key.
        writer.open(header: fileHeaderLine())
        deviceState.start(onChange: makeDeviceStateHandler())
        installDispatcher()

        emit(
            src: .app,
            tag: "Diagnostics",
            level: .info,
            message: "Diagnostic session started\(DiagnosticLog.delimiter)"
                + "ev=session.start io=obs schema=\(DiagnosticLogSchema.version) "
                + "dir=\(DiagnosticLog.directory.lastPathComponent)"
        )
    }

    /// `nonisolated` on purpose: a closure formed inside a `@MainActor` method inherits that
    /// isolation, and the SDK calls the dispatcher from any thread — which hard-traps under Swift 6.
    private nonisolated func installDispatcher() {
        let logger = CioInternalCommon.DIGraphShared.shared.logger
        // The SDK filters by level *before* reaching the dispatcher, so a sink installed while the
        // level sits at its `.error` default sees nothing. Forced here and again in the config
        // builder, because `CustomerIO.initialize` re-applies the configured level over this one.
        logger.setLogLevel(.debug)
        logger.setLogDispatcher { [weak self] level, message in
            self?.dispatch(level: level, message: message)
        }
    }

    private nonisolated func makeDeviceStateHandler() -> @Sendable (String) -> Void {
        { [weak self] reason in
            self?.emit(
                src: .app,
                tag: "Diagnostics",
                level: .debug,
                message: "Device state changed\(DiagnosticLog.delimiter)ev=device.state io=obs changed=\(reason)"
            )
        }
    }

    // MARK: - Ingest

    /// Receives every record the SDK emits. Forwards to the platform logger **first**: both SDKs
    /// implement dispatch as `logDispatcher?(...) ?? systemLogger.log(...)`, so a dispatcher that
    /// does not forward silently empties the Xcode console for everyone else using this app.
    private func dispatch(level: CioLogLevel, message: String) {
        systemLogger.log(message, level)

        // The SDK has already prefixed `[Tag] `. Lift it into its own field so files can be
        // filtered by subsystem, and leave the rest of the string untouched.
        let (tag, body) = DiagnosticLog.splitTag(from: message)
        emit(src: .sdk, tag: tag, level: level, message: body)
    }

    /// Write an app-side record, for anything the SDK does not say itself. Mirrors Android's
    /// `DiagnosticLog.note`.
    func note(_ message: String, tag: String = "Diagnostics", level: CioLogLevel = .debug) {
        emit(src: .app, tag: tag, level: level, message: message)
    }

    private func emit(src: Source, tag: String?, level: CioLogLevel, message: String) {
        // Evaluated before the lock and before any string is built: a dropped record should cost a
        // predicate, not an envelope and a device-state snapshot.
        guard DiagnosticFilter.shouldRecord(src: src, tag: tag, level: level, message: message) else { return }
        lock.lock()
        defer { lock.unlock() }
        guard started, !isEmitting else { return }
        isEmitting = true
        defer { isEmitting = false }

        seq += 1
        let now = Date()
        let mono = DiagnosticClock.monotonicNanos()
        let up = startMono == 0 ? 0 : (mono &- startMono) / 1000000

        var line = "{"
        line += "\"v\":\(DiagnosticLogSchema.version)"
        line += ",\"seq\":\(seq)"
        line += ",\"ts\":\(DiagnosticJSON.string(DiagnosticClock.iso8601(now)))"
        line += ",\"mono\":\(mono)"
        line += ",\"pid\":\(pid)"
        line += ",\"up\":\(up)"
        line += ",\"src\":\(DiagnosticJSON.string(src.rawValue))"
        if let tag = tag {
            line += ",\"tag\":\(DiagnosticJSON.string(tag))"
        }
        line += ",\"lvl\":\(DiagnosticJSON.string(level.rawValue))"
        line += ",\"msg\":\(DiagnosticJSON.string(message))"
        // Omitted when unchanged since the last record that carried it (schema 2).
        if let dev = devStateForRecord() {
            line += ",\"dev\":\(dev)"
        }
        line += "}"

        writer.append(line)
    }

    /// Returns the snapshot to embed, or `nil` to omit `dev` from this record.
    private func devStateForRecord() -> String? {
        let current = deviceState.snapshotJSON()
        let now = Date()
        let elapsed = lastDevAt.map { now.timeIntervalSince($0) } ?? .greatestFiniteMagnitude
        let forced = lastDevJSON == nil
            || recordsSinceDev >= devHeartbeatRecords
            || elapsed >= devHeartbeat
        if !forced, current == lastDevJSON {
            recordsSinceDev += 1
            return nil
        }
        lastDevJSON = current
        lastDevAt = now
        recordsSinceDev = 0
        return current
    }

    /// Called when the writer opens a file, so the first record there always carries `dev`.
    func resetDeviceStateCadence() {
        lock.lock()
        defer { lock.unlock() }
        lastDevJSON = nil
    }

    // MARK: - File header

    /// First line of every file. `boot` matters: `mono` values are only comparable to each other
    /// within a single boot, so a file that does not name its boot cannot be aligned with another.
    private func fileHeaderLine() -> String {
        let bundle = Bundle.main
        let appVersion = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let appBuild = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"

        var line = "{"
        line += "\"v\":\(DiagnosticLogSchema.version)"
        line += ",\"ev\":\"file.open\""
        // Without this a filtered file is silently lossy: nothing in it separates "in-app was
        // quiet" from "in-app was removed", and a reader would draw the wrong conclusion.
        line += ",\"filter\":\(DiagnosticFilter.headerJSON())"
        line += ",\"ts\":\(DiagnosticJSON.string(DiagnosticClock.iso8601(Date())))"
        line += ",\"boot\":\(DiagnosticJSON.string(DiagnosticClock.bootIdentifier()))"
        line += ",\"device\":{"
        line += "\"model\":\(DiagnosticJSON.string(DiagnosticDeviceState.hardwareModel()))"
        line += ",\"os\":\"iOS\""
        line += ",\"osVersion\":\(DiagnosticJSON.string(ProcessInfo.processInfo.operatingSystemVersionString))"
        line += "}"
        line += ",\"app\":{"
        line += "\"id\":\(DiagnosticJSON.string(bundle.bundleIdentifier ?? "unknown"))"
        line += ",\"version\":\(DiagnosticJSON.string(appVersion))"
        line += ",\"build\":\(DiagnosticJSON.string(appBuild))"
        line += "}"
        line += ",\"sdk\":{\"version\":\(DiagnosticJSON.string(SdkVersion.version))}"
        line += ",\"tz\":\(DiagnosticJSON.string(TimeZone.current.identifier))"
        line += "}"
        return line
    }

    // MARK: - Helpers

    /// Splits `[Geofence] message` into `("Geofence", "message")`. A message with no prefix keeps
    /// its whole text and reports no tag.
    static func splitTag(from message: String) -> (tag: String?, body: String) {
        guard message.hasPrefix("["), let close = message.firstIndex(of: "]") else {
            return (nil, message)
        }
        let tag = String(message[message.index(after: message.startIndex) ..< close])
        var rest = String(message[message.index(after: close)...])
        if rest.hasPrefix(" ") {
            rest.removeFirst()
        }
        return (tag.isEmpty ? nil : tag, rest)
    }

    /// Files currently on disk, newest first.
    func sessionFiles() -> [URL] {
        writer.files()
    }
}
