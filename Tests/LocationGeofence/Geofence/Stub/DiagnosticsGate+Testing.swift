@testable import CioLocationGeofence
import Foundation

/// `GeofenceDiagnostics.overrideForTesting` is process-global, and swift-testing's `.serialized`
/// orders tests *within* a suite, not across them. Two suites both flipping the gate therefore
/// raced: one asserting "no diagnostic keys with the gate off" would intermittently observe the
/// other's `true`, roughly one run in four.
///
/// Every test that touches the gate takes this lock for the whole of its body, which serializes
/// them across suite boundaries without restructuring either suite.
///
/// **Synchronous only, deliberately.** An `async` variant existed and deadlocked: a lock held
/// across an `await` can be released on a different cooperative-pool thread than took it, so
/// `unlock()` fails with EPERM and every later caller blocks forever. It hung the whole target
/// intermittently. No lock can be held across a suspension point, so the fix is not a better lock
/// — a test that needs the gate must not await inside it. The one test that did now asserts on
/// prose instead, which needs no gate at all.
enum DiagnosticsGateTesting {
    private static let lock = NSRecursiveLock()

    /// Runs `body` with the gate forced on or off, restoring the previous value after.
    static func withDiagnostics<T>(_ enabled: Bool, _ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        let previous = GeofenceDiagnostics.overrideForTesting
        GeofenceDiagnostics.overrideForTesting = enabled
        defer { GeofenceDiagnostics.overrideForTesting = previous }
        return try body()
    }
}
