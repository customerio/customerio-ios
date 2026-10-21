import Foundation

/// What a dwell diagnostic entry records. Persisted by case name; an entry naming an unknown one is skipped,
/// so a case stays here once any build has written it.
///
/// `wakeRegion` and `wakeVisit` record that a region or visit callback ran, which can happen while the app
/// is already running; `wakeForeground` records a return to the foreground. None shows on its own that iOS
/// woke or resumed the process. `wakeSession` is what earlier builds wrote for any session callback,
/// whatever its kind: still read, no longer written. The `session*Callback` cases name the kind instead,
/// and the same caution applies to them.
enum DwellDiagnosticEvent: String, CaseIterable, Sendable {
    case deadlineScheduled, deadlineReached, deadlineCancelled
    case wakeRegion, wakeVisit, wakeForeground, wakeSession
    case fixRequested, fixReceived
    case sessionStarted, sessionStopped
    case dwellRejected, dwellEmitted
    case sessionLocationCallback, sessionErrorCallback, sessionAuthorizationCallback
}

/// Why an entry happened, where its event alone does not say. Persisted by case name; an unknown one reads as nil.
enum DwellDiagnosticReason: String, CaseIterable, Sendable {
    case notInside, undecided, noFix, staleFix, belowThreshold
    case visitEnded, identityChanged, revisionChanged, permissionLost
    case capReached, retriesExhausted, optedOut
}

/// Timing and fix-quality metadata only: no coordinate, location object, user or device identity,
/// wall-clock date or free-form map. Times are `GeofenceClockReading.uptime` seconds, which restart at
/// boot. Bounds apply on construction, so every record a journal holds or returns is bounded.
struct DwellDiagnosticRecord: Equatable, Sendable {
    static let maxFenceIdScalars = 128
    static let maxLabelScalars = 32

    let event: DwellDiagnosticEvent
    let atUptime: TimeInterval
    let fenceId: String?
    let deadlineUptime: TimeInterval?
    let reason: DwellDiagnosticReason?
    /// A label for what was asked of Core Location, such as an accuracy constant's name.
    let requestedAccuracy: String?
    /// Metres, as Core Location reported them.
    let returnedAccuracy: Double?
    let fixAge: TimeInterval?

    /// Nil unless `atUptime` is finite and non-negative. Other numbers that are not are dropped, and
    /// strings are cut to a bounded count of Unicode scalars, so they stay valid Unicode.
    init?(
        event: DwellDiagnosticEvent,
        atUptime: TimeInterval,
        fenceId: String? = nil,
        deadlineUptime: TimeInterval? = nil,
        reason: DwellDiagnosticReason? = nil,
        requestedAccuracy: String? = nil,
        returnedAccuracy: Double? = nil,
        fixAge: TimeInterval? = nil
    ) {
        guard let atUptime = Self.nonNegative(atUptime) else { return nil }
        self.event = event
        self.atUptime = atUptime
        self.fenceId = Self.bounded(fenceId, to: Self.maxFenceIdScalars)
        self.deadlineUptime = deadlineUptime.flatMap(Self.nonNegative)
        self.reason = reason
        self.requestedAccuracy = Self.bounded(requestedAccuracy, to: Self.maxLabelScalars)
        self.returnedAccuracy = returnedAccuracy.flatMap(Self.nonNegative)
        self.fixAge = fixAge.flatMap(Self.nonNegative)
    }

    private static func nonNegative(_ value: Double) -> Double? {
        value.isFinite && value >= 0 ? value : nil
    }

    private static func bounded(_ value: String?, to limit: Int) -> String? {
        guard let value, !value.isEmpty else { return nil }
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: value.unicodeScalars.prefix(limit))
        return String(scalars)
    }
}

/// The identity a journal's history is kept for: the context store's opaque identity version and
/// lineage, never a user id. Stored beside the history, never in an exported record.
struct DwellDiagnosticOwner: Codable, Equatable, Sendable {
    static let maxLineageScalars = 128

    let version: UInt64
    let lineage: String

    /// Nil for an empty or over-long lineage, which binds nothing: a cut one could match another's.
    init?(_ identity: GeofenceIdentity) {
        guard !identity.lineage.isEmpty, identity.lineage.unicodeScalars.count <= Self.maxLineageScalars else {
            return nil
        }
        self.version = identity.version
        self.lineage = identity.lineage
    }
}

/// Opt-in, bounded, on-device dwell diagnostics in one file, under a directory the journal owns.
/// Nothing it does throws to its caller. Bytes that do not decode as this journal's are replaced by the
/// next append; a read that fails is not, so a transient I/O error discards no history. Fence ids with
/// times are location-derived history: an append naming its owner first clears history kept for any
/// other, and callers clear it on reset and once the host has opted out. Use one instance per
/// directory; instances do not coordinate with each other.
actor DwellDiagnosticJournal {
    /// The host's explicit opt-in: a Boolean in its Info.plist. Absent, or any other value, is off.
    static let infoPlistKey = "CIOGeofenceExperimentalDwellDiagnosticJournal"
    static let defaultCapacity = 64
    static let maxCapacity = 256
    /// 2 KiB covers a record's worst case, every string scalar escaped to six bytes, so the journal
    /// never refuses a file it wrote.
    static let maxFileBytes = maxCapacity * 2048 + 1024
    /// Covers an owner's worst case, its bounded lineage escaped, as `maxFileBytes` covers the records'.
    static let maxOwnerBytes = 2048
    static let provider = "core_location"
    private static let version = 1

    private let ownDirectory: URL
    private let file: URL
    private let ownerFile: URL
    /// The owner this instance last found or wrote, so a bound append reads the stored one once.
    private var verifiedOwner: DwellDiagnosticOwner?
    private let capacity: Int
    private let isEnabled: @Sendable () -> Bool

    /// Touches no file; the first call does.
    init(
        directory: URL,
        capacity: Int = DwellDiagnosticJournal.defaultCapacity,
        isEnabled: @escaping @Sendable () -> Bool
    ) {
        self.ownDirectory = Self.storeDirectory(in: directory)
        self.file = Self.fileURL(in: directory)
        self.ownerFile = Self.storeDirectory(in: directory).appendingPathComponent("owner-v1.json", isDirectory: false)
        self.capacity = min(max(capacity, 1), Self.maxCapacity)
        self.isEnabled = isEnabled
    }

    static func storeDirectory(in directory: URL) -> URL {
        directory.appendingPathComponent("io.customer.dwell-diagnostics", isDirectory: true)
    }

    static func fileURL(in directory: URL) -> URL {
        storeDirectory(in: directory).appendingPathComponent("journal-v1.json", isDirectory: false)
    }

    static func isOptedIn(in bundle: Bundle) -> Bool {
        bundle.object(forInfoDictionaryKey: infoPlistKey) as? Bool ?? false
    }

    /// Whether `record` was persisted. False, writing nothing, when opted out, when the calling task is
    /// cancelled, when stored history exists but cannot be read, or when `owner` cannot be prepared.
    /// With an `owner`, history kept for any other is cleared first; without one the append is unbound.
    func append(_ record: DwellDiagnosticRecord, owner: DwellDiagnosticOwner? = nil) -> Bool {
        guard !Task.isCancelled, isEnabled() else { return false }
        if let owner, !prepareOwner(owner) { return false }
        var records: [DwellDiagnosticRecord]
        switch load() {
        case .missing, .corrupt: records = []
        case .records(let existing): records = existing
        case .unreadable: return false
        }
        records.append(record)
        guard let data = try? Self.encode(Array(records.suffix(capacity))),
              data.count <= Self.maxFileBytes,
              !Task.isCancelled
        else { return false }
        return write(data, to: file)
    }

    /// Keeps the history only while it is `owner`'s. History kept for another owner, for none (written
    /// before owners were), or for one that does not decode is cleared before `owner` is recorded.
    /// False, writing nothing, when opted out, or when the stored owner cannot be read or `owner` written.
    func prepareOwner(_ owner: DwellDiagnosticOwner) -> Bool {
        guard isEnabled() else { return false }
        if verifiedOwner == owner { return true }
        let stored: DwellDiagnosticOwner?
        do { stored = try storedOwner() } catch { return false }
        if stored != owner {
            guard clear(), let data = try? JSONEncoder().encode(owner), write(data, to: ownerFile) else {
                return false
            }
        }
        verifiedOwner = owner
        return true
    }

    /// Nil when none is stored or the bytes are not an owner. Throws when the file cannot be read, which
    /// keeps the history, as `load` does.
    private func storedOwner() throws -> DwellDiagnosticOwner? {
        let manager = FileManager.default
        guard manager.fileExists(atPath: ownerFile.path) else { return nil }
        let size = try (manager.attributesOfItem(atPath: ownerFile.path)[.size] as? NSNumber)?.intValue
        guard let size, size <= Self.maxOwnerBytes else { return nil }
        let data = try Data(contentsOf: ownerFile)
        return try? JSONDecoder().decode(DwellDiagnosticOwner.self, from: data)
    }

    /// Atomically, into the journal's own directory.
    private func write(_ data: Data, to url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: ownDirectory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
            // Device-only history: kept out of backups, and so off other devices.
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var directory = ownDirectory
            try directory.setResourceValues(values)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            return false
        }
    }

    /// Oldest first, at most `capacity`. Empty when opted out; nil when stored history is unreadable.
    func snapshot() -> [DwellDiagnosticRecord]? {
        guard isEnabled() else { return [] }
        switch load() {
        case .missing: return []
        case .records(let records): return Array(records.suffix(capacity))
        case .corrupt, .unreadable: return nil
        }
    }

    /// Removes the history and its owner whether or not the host is opted in. True once nothing is
    /// stored.
    @discardableResult
    func clear() -> Bool {
        verifiedOwner = nil
        do {
            try FileManager.default.removeItem(at: ownDirectory)
            return true
        } catch {
            return !FileManager.default.fileExists(atPath: ownDirectory.path)
        }
    }

    private enum Load {
        case missing
        case records([DwellDiagnosticRecord])
        /// Bytes that are not this journal's: the next append replaces them.
        case corrupt
        /// A file that exists but could not be read: kept.
        case unreadable
    }

    private func load() -> Load {
        let manager = FileManager.default
        guard manager.fileExists(atPath: file.path) else { return .missing }
        let data: Data
        do {
            // Sized before it is read, so a damaged or foreign file is never loaded whole.
            let size = try (manager.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue
            guard let size, size <= Self.maxFileBytes else { return .corrupt }
            data = try Data(contentsOf: file)
        } catch {
            return .unreadable
        }
        guard data.count <= Self.maxFileBytes,
              let stored = try? JSONDecoder().decode(Stored.self, from: data),
              stored.version == Self.version,
              stored.provider == Self.provider
        else { return .corrupt }
        return .records(stored.records.compactMap(\.record))
    }

    private static func encode(_ records: [DwellDiagnosticRecord]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let stored = Stored(version: version, provider: provider, records: records.map { StoredRecord($0) })
        return try encoder.encode(stored)
    }

    private struct Stored: Codable {
        let version: Int
        let provider: String
        let records: [StoredRecord]
    }

    /// Read back through `DwellDiagnosticRecord`'s bounds: the file may not be one this journal wrote.
    private struct StoredRecord: Codable {
        let event: String
        let atUptime: Double
        let fenceId: String?
        let deadlineUptime: Double?
        let reason: String?
        let requestedAccuracy: String?
        let returnedAccuracy: Double?
        let fixAge: Double?

        init(_ record: DwellDiagnosticRecord) {
            self.event = record.event.rawValue
            self.atUptime = record.atUptime
            self.fenceId = record.fenceId
            self.deadlineUptime = record.deadlineUptime
            self.reason = record.reason?.rawValue
            self.requestedAccuracy = record.requestedAccuracy
            self.returnedAccuracy = record.returnedAccuracy
            self.fixAge = record.fixAge
        }

        var record: DwellDiagnosticRecord? {
            guard let event = DwellDiagnosticEvent(rawValue: event) else { return nil }
            return DwellDiagnosticRecord(
                event: event,
                atUptime: atUptime,
                fenceId: fenceId,
                deadlineUptime: deadlineUptime,
                reason: reason.flatMap(DwellDiagnosticReason.init(rawValue:)),
                requestedAccuracy: requestedAccuracy,
                returnedAccuracy: returnedAccuracy,
                fixAge: fixAge
            )
        }
    }
}
