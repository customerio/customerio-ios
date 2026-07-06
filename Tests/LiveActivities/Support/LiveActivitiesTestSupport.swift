import CioInternalCommon
import Foundation

@testable import CioLiveActivities

/// No-op `Logger` for tests that only need the dependency satisfied.
final class NoopLogger: Logger {
    var logLevel: CioLogLevel = .error
    func setLogDispatcher(_ dispatcher: ((CioLogLevel, String) -> Void)?) {}
    func setLogLevel(_ level: CioLogLevel) {}
    func debug(_ message: String, _ tag: String?) {}
    func info(_ message: String, _ tag: String?) {}
    func error(_ message: String, _ tag: String?, _ throwable: Error?) {}
}

/// Captures the events a `LiveActivityReporter` would send, plus controllable identity, so
/// tests can drive gating and dedup deterministically.
final class TrackCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [(name: String, properties: [String: Any])] = []
    var events: [(name: String, properties: [String: Any])] { lock.withLock { _events } }
    var userId: String?
    var deviceToken: String?

    func record(_ name: String, _ properties: [String: Any]) {
        lock.withLock { _events.append((name, properties)) }
    }

    func makeReporter() -> LiveActivityReporter {
        LiveActivityReporter(
            track: { name, props in self.record(name, props) },
            currentUserId: { self.userId },
            deviceToken: { self.deviceToken },
            logger: NoopLogger()
        )
    }

    var count: Int { events.count }
    // Defined via `events.isEmpty` (not `count == 0`) so SwiftLint's empty_count autofix
    // doesn't rewrite it into a self-referential loop.
    var isEmpty: Bool { events.isEmpty }
    func string(_ index: Int, _ key: String) -> String? {
        events[index].properties[key] as? String
    }
}

/// In-memory `SharedKeyValueStorage` for exercising `KeyValueLiveActivityTokenStore`
/// without touching real UserDefaults.
final class InMemoryKeyValueStorage: SharedKeyValueStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var store: [String: Any] = [:]

    func integer(_ key: KeyValueStorageKey) -> Int? {
        lock.withLock { store[key.rawValue] as? Int }
    }

    func setInt(_ value: Int?, forKey key: KeyValueStorageKey) {
        set(value, key)
    }

    func double(_ key: KeyValueStorageKey) -> Double? {
        lock.withLock { store[key.rawValue] as? Double }
    }

    func setDouble(_ value: Double?, forKey key: KeyValueStorageKey) {
        set(value, key)
    }

    func string(_ key: KeyValueStorageKey) -> String? {
        lock.withLock { store[key.rawValue] as? String }
    }

    func setString(_ value: String?, forKey key: KeyValueStorageKey) {
        set(value, key)
    }

    func date(_ key: KeyValueStorageKey) -> Date? {
        lock.withLock { store[key.rawValue] as? Date }
    }

    func setDate(_ value: Date?, forKey key: KeyValueStorageKey) {
        set(value, key)
    }

    func data(_ key: KeyValueStorageKey) -> Data? {
        lock.withLock { store[key.rawValue] as? Data }
    }

    func setData(_ value: Data?, forKey key: KeyValueStorageKey) {
        set(value, key)
    }

    func deleteAll() {
        lock.withLock { store.removeAll() }
    }

    private func set(_ value: Any?, _ key: KeyValueStorageKey) {
        lock.withLock {
            if let value { store[key.rawValue] = value } else { store[key.rawValue] = nil }
        }
    }
}

/// In-memory `LiveActivityTokenStorage` for registrar tests.
final class FakeTokenStore: LiveActivityTokenStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var _signatures: [String: String] = [:]
    var signatures: [String: String] { lock.withLock { _signatures } }

    func registrationSignature(activityType: String) -> String? {
        lock.withLock { _signatures[activityType] }
    }

    func setRegistrationSignature(activityType: String, signature: String) {
        lock.withLock { _signatures[activityType] = signature }
    }

    func clearRegistrationSignature(activityType: String) {
        lock.withLock { _signatures[activityType] = nil }
    }

    func allRegistrationKeys() -> [String] {
        lock.withLock { Array(_signatures.keys) }
    }

    func clearAll() {
        lock.withLock { _signatures.removeAll() }
    }
}
