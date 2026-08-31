import CioInternalCommon
import Foundation
import UIKit

/// Field-drive diagnostics sink.
///
/// Installs a dispatcher on the Customer.io logger and mirrors every record the SDK emits into an
/// NDJSON file on disk, together with a device-state snapshot.
///
/// Geofence field drives run for hours with the app in the background and no debugger attached.
/// Most geofence logging is `debug`, which never reaches the unified log store, so today a
/// completed drive leaves essentially nothing to analyse afterwards. This is the sink that fixes
/// that.
///
/// **Nothing here parses the SDK's message.** The device writes the raw string, including any
/// ` || key=value` tail, into `msg`. A host-side script splits the tail and fills in `ev` and
/// `data`. One parser, living off-device, means no Swift/Kotlin pair to drift apart and a parser
/// bug can be fixed and re-run over files we already captured, instead of having destroyed what
/// it misread.
enum DiagnosticLogSchema {
    /// Bumped only when a field is removed, renamed, or changes meaning. Adding an optional
    /// field is not a bump — parsers ignore unknown fields.
    static let version = 1
}

final class DiagnosticLog: @unchecked Sendable {
    static let shared = DiagnosticLog()

    /// Records produced by the SDK's logger, by the sample app itself, or by a reference app
    /// emitting this same schema.
    enum Source: String {
        case sdk
        case app
        case ref
    }

    private let lock = NSRecursiveLock()
    private let writer: DiagnosticLogWriter
    private let deviceState = DiagnosticDeviceState()
    /// The SDK's own console logger, reached through the shared graph so forwarded records land
    /// in Xcode and Console.app byte-identically to how they would without a dispatcher installed.
    private let systemLogger: SystemLogger = CioInternalCommon.DIGraphShared.shared.systemLogger

    private var seq = 0
    private var started = false
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
    ///
    /// A cold background wake reaches geofence code within milliseconds of process start. Install
    /// this lazily — on a settings screen, after SDK initialization, from a scene delegate — and
    /// the wake you most wanted to observe is already over.
    @MainActor
    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard !started else { return }
        started = true
        startMono = DiagnosticClock.monotonicNanos()

        // Internal SDK diagnostics: the machine-readable tail the harness parses. Off by default
        // in the SDK and unreachable from a customer app; on here because this app exists to
        // produce field data. See CioDiagnostics for why the default must stay false.
        CioDiagnostics.enabled = true

        writer.open(header: fileHeaderLine())
        deviceState.start(onChange: makeDeviceStateHandler())
        installDispatcher()

        emit(
            src: .app,
            tag: "Diagnostics",
            level: .info,
            message: "session.start schema=\(DiagnosticLogSchema.version) dir=\(DiagnosticLog.directory.lastPathComponent)"
        )
    }

    /// Both callback-installing helpers are `nonisolated` on purpose, and it is not a style
    /// preference.
    ///
    /// A closure formed inside a `@MainActor` function inherits main-actor isolation. The SDK
    /// calls its log dispatcher from whatever thread it happens to be logging on, and under
    /// Swift 6 that mismatch is not a warning — it traps in `swift_task_isCurrentExecutorImpl`.
    /// Installed from `start()` directly, this sink takes the whole app down on the first log line
    /// the SDK emits off the main thread, which on a field drive is essentially all of them.
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
            self?.emit(src: .app, tag: "Diagnostics", level: .debug, message: "device.state changed=\(reason)")
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

    /// Write an app-side record. Used for anything the SDK does not say itself.
    func note(_ message: String, tag: String = "Diagnostics", level: CioLogLevel = .debug) {
        emit(src: .app, tag: tag, level: level, message: message)
    }

    private func emit(src: Source, tag: String?, level: CioLogLevel, message: String) {
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
        line += ",\"dev\":\(deviceState.snapshotJSON())"
        line += "}"

        writer.append(line)
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
