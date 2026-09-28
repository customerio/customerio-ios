@testable import CioLocationGeofence
import Foundation

/// Forces the diagnostics gate on or off for the duration of `body`.
///
/// Outside it, `GeofenceLog.tail` returns "" unless the Info.plist gate is on, so `ev=`, `state=`
/// and every other key are absent from the message. Such a test must assert on the log's prose
/// instead, as `GeofenceVisitMonitorTests` does.
enum DiagnosticsGateTesting {
    /// Task-local, so suites running in parallel do not see each other's value.
    static func withDiagnostics<T>(_ enabled: Bool, _ body: () throws -> T) rethrows -> T {
        try GeofenceDiagnostics.$overrideForTesting.withValue(enabled, operation: body)
    }

    /// Async counterpart, for a body that awaits.
    static func withDiagnostics<T>(_ enabled: Bool, _ body: () async throws -> T) async rethrows -> T {
        try await GeofenceDiagnostics.$overrideForTesting.withValue(enabled, operation: body)
    }
}
