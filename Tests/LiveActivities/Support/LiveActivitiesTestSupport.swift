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

/// In-memory `LiveActivityTokenStorage` for registrar tests.
final class FakeTokenStore: LiveActivityTokenStorage {
    private(set) var signatures: [String: String] = [:]

    func registrationSignature(activityType: String) -> String? {
        signatures[activityType]
    }

    func setRegistrationSignature(activityType: String, signature: String) {
        signatures[activityType] = signature
    }

    func clearAll() {
        signatures.removeAll()
    }
}
