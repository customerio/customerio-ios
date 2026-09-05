@testable import CioInternalCommon
@testable import CioLocationGeofence
import CoreLocation
import Foundation
import Testing

/// The delegate is shared. A host app monitoring its own `CLCircularRegion`s gets those crossings
/// delivered to the same `locationManager(_:didEnterRegion:)` we implement, so anything recorded
/// before the ownership check describes a crossing the SDK has nothing to do with — and writes the
/// host's region identifier into a capture that gets shared around.
@Suite("CoreLocationGeofenceMonitor ownership boundary", .serialized)
@MainActor
struct GeofenceMonitorOwnershipTests {
    private final class CapturingLogger: Logger, @unchecked Sendable {
        private let lock = NSLock()
        private var captured: [String] = []

        var messages: [String] {
            lock.lock()
            defer { lock.unlock() }
            return captured
        }

        var logLevel: CioLogLevel = .debug
        func setLogDispatcher(_: ((CioLogLevel, String) -> Void)?) {}
        func setLogLevel(_ level: CioLogLevel) {
            logLevel = level
        }

        func debug(_ message: String, _ tag: String?) {
            record(message, tag)
        }

        func info(_ message: String, _ tag: String?) {
            record(message, tag)
        }

        func error(_ message: String, _ tag: String?, _ error: Error?) {
            record(error.map { "\(message) Error: \($0.localizedDescription)" } ?? message, tag)
        }

        private func record(_ message: String, _ tag: String?) {
            lock.lock()
            defer { lock.unlock() }
            captured.append(tag.map { "[\($0)] \(message)" } ?? message)
        }
    }

    private static let hostIdentifier = "host_app_loyalty_store_4471"

    /// The `ev=` tail only exists when diagnostics are on. Without this the assertions below match
    /// nothing and pass against the very bug they are meant to catch — verified by running them
    /// against the unfixed monitor.
    private func withDiagnostics<T>(_ enabled: Bool, _ body: () throws -> T) rethrows -> T {
        try DiagnosticsGateTesting.withDiagnostics(enabled, body)
    }

    private func hostRegion() -> CLCircularRegion {
        CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: 25.109908, longitude: 55.184004),
            radius: 100,
            identifier: Self.hostIdentifier
        )
    }

    /// Immediate path: a handler is bound and nothing is queued, so the crossing is evaluated
    /// against ownership straight away.
    @Test
    func regionEvent_givenRegionNotOurs_expectNothingRecorded() {
        withDiagnostics(true) {
            let logger = CapturingLogger()
            let monitor = CoreLocationGeofenceMonitor(logger: logger)
            monitor.setOnTransition { _, _, _ in }

            monitor.locationManager(CLLocationManager(), didEnterRegion: hostRegion())

            #expect(
                !monitor.monitoredRegionIdentifiers.contains(Self.hostIdentifier),
                "precondition: the region must not be one of ours"
            )
            #expect(
                logger.messages.allSatisfy { !$0.contains("os.callback.received") },
                "recorded a crossing for a region we do not own: \(logger.messages)"
            )
        }
    }

    /// The identifier itself must not reach the log by any route. The tail is gated behind the
    /// diagnostics flag, but the prose half of the record is not, so a leak here would ship even
    /// with diagnostics off.
    @Test
    func regionEvent_givenRegionNotOurs_expectIdentifierNeverLogged() {
        let logger = CapturingLogger()
        let monitor = CoreLocationGeofenceMonitor(logger: logger)
        monitor.setOnTransition { _, _, _ in }

        monitor.locationManager(CLLocationManager(), didExitRegion: hostRegion())

        #expect(
            logger.messages.allSatisfy { !$0.contains(Self.hostIdentifier) },
            "host app's region identifier reached a capture we hand around: \(logger.messages)"
        )
    }

    /// Buffered path: with no handler bound the crossing queues, and ownership is only checked when
    /// the queue drains. Nothing may be recorded in the meantime.
    @Test
    func regionEvent_givenBufferedAndNotOurs_expectNothingRecorded() async {
        await DiagnosticsGateTesting.withDiagnostics(true) {
            let logger = CapturingLogger()
            let monitor = CoreLocationGeofenceMonitor(logger: logger)

            monitor.locationManager(CLLocationManager(), didEnterRegion: hostRegion())
            monitor.setOnTransition { _, _, _ in }
            // Let the drain task run; it is dispatched onto the main actor.
            await Task.yield()

            #expect(
                logger.messages.allSatisfy { !$0.contains("os.callback.received") },
                "drained a buffered crossing for a region we do not own: \(logger.messages)"
            )
        }
    }
}
