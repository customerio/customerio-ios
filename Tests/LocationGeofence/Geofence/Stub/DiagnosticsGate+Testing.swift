@testable import CioLocationGeofence
import Foundation

/// Outside `withDiagnostics(true)`, `GeofenceLog.tail` returns "", so tail keys are absent from
/// messages.
enum DiagnosticsGateTesting {
    /// Task-local, so parallel suites don't see each other's value.
    static func withDiagnostics<T>(_ enabled: Bool, _ body: () throws -> T) rethrows -> T {
        try GeofenceDiagnostics.$overrideForTesting.withValue(enabled, operation: body)
    }

    static func withDiagnostics<T>(_ enabled: Bool, _ body: () async throws -> T) async rethrows -> T {
        try await GeofenceDiagnostics.$overrideForTesting.withValue(enabled, operation: body)
    }
}
