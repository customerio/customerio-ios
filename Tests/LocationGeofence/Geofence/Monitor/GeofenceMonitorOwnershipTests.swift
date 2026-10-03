@testable import CioInternalCommon
@testable import CioLocationGeofence
import CoreLocation
import Foundation
import Testing

/// The delegate is shared, so it also receives crossings for the host app's own regions.
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

    /// Without diagnostics there is no `ev=` tail, and the `ev=` assertions pass vacuously.
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

    @Test
    func regionEvent_givenRegionNotOurs_expectNothingRecorded() {
        withDiagnostics(true) {
            let logger = CapturingLogger()
            let monitor = CoreLocationGeofenceMonitor(logger: logger)
            monitor.setOnTransition { _, _, _, _, _, _, _ in }

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

    /// Diagnostics off on purpose: the prose half of the record isn't gated.
    @Test
    func regionEvent_givenRegionNotOurs_expectIdentifierNeverLogged() {
        let logger = CapturingLogger()
        let monitor = CoreLocationGeofenceMonitor(logger: logger)
        monitor.setOnTransition { _, _, _, _, _, _, _ in }

        monitor.locationManager(CLLocationManager(), didExitRegion: hostRegion())

        #expect(
            logger.messages.allSatisfy { !$0.contains(Self.hostIdentifier) },
            "host app's region identifier reached a capture we hand around: \(logger.messages)"
        )
    }

    private final class InterruptionRecorder {
        var identifiers: [String?] = []
    }

    /// Core Location may report a failure without saying which region stopped. No active visit can
    /// then prove it was watched throughout, so continuity is invalidated for all of them.
    @Test
    func monitoringFailure_givenNoRegion_expectGlobalContinuityInvalidation() {
        let monitor = CoreLocationGeofenceMonitor(logger: CapturingLogger())
        let recorder = InterruptionRecorder()
        monitor.setOnMonitoringInterrupted { recorder.identifiers.append($0) }

        monitor.locationManager(
            CLLocationManager(),
            monitoringDidFailFor: nil,
            withError: CLError(.regionMonitoringFailure)
        )

        #expect(recorder.identifiers.count == 1)
        #expect(recorder.identifiers.first == .some(nil))
    }

    /// A host app's region failing says nothing about ours.
    @Test
    func monitoringFailure_givenRegionNotOurs_expectNoInvalidation() {
        let monitor = CoreLocationGeofenceMonitor(logger: CapturingLogger())
        let recorder = InterruptionRecorder()
        monitor.setOnMonitoringInterrupted { recorder.identifiers.append($0) }

        monitor.locationManager(
            CLLocationManager(),
            monitoringDidFailFor: hostRegion(),
            withError: CLError(.regionMonitoringFailure)
        )

        #expect(recorder.identifiers.isEmpty)
    }

    @Test
    func regionEvent_givenBufferedAndNotOurs_expectNothingRecorded() async {
        let logger = CapturingLogger()
        let monitor = CoreLocationGeofenceMonitor(logger: logger)

        monitor.locationManager(CLLocationManager(), didEnterRegion: hostRegion())
        monitor.setOnTransition { _, _, _, _, _, _, _ in }
        await Task.yield()

        // Asserts on the identifier, not `ev=`, so it can't pass vacuously with diagnostics off.
        #expect(
            logger.messages.allSatisfy { !$0.contains(Self.hostIdentifier) },
            "drained a buffered crossing for a region we do not own: \(logger.messages)"
        )
    }
}
