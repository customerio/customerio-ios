@testable import CioInternalCommon
@testable import CioLocationGeofence
import CoreLocation
import Foundation
import Testing

/// iOS 13–17 run the classic monitor, where a polygon arrives as its covering circle.
@Suite("CoreLocationGeofenceMonitor polygon path", .serialized)
@MainActor
struct GeofenceClassicPolygonPathTests {
    private static let polygonId = "polygon_fence"
    private static let center = LocationData(latitude: 31.37143, longitude: 74.18527)
    private static let coveringRadius: Double = 104

    private final class SilentLogger: Logger, @unchecked Sendable {
        var logLevel: CioLogLevel = .none
        func setLogDispatcher(_: ((CioLogLevel, String) -> Void)?) {}
        func setLogLevel(_ level: CioLogLevel) {
            logLevel = level
        }

        func debug(_: String, _: String?) {}
        func info(_: String, _: String?) {}
        func error(_: String, _: String?, _: Error?) {}
    }

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

        private func record(_ message: String) {
            lock.lock()
            defer { lock.unlock() }
            captured.append(message)
        }

        func debug(_ message: String, _: String?) {
            record(message)
        }

        func info(_ message: String, _: String?) {
            record(message)
        }

        func error(_ message: String, _: String?, _: Error?) {
            record(message)
        }
    }

    private struct Delivered {
        let identifier: String
        let transition: GeofenceTransition
        let circle: GeofenceEventCircle
    }

    private func makeMonitor(
        onTransition: @escaping (Delivered) -> Void
    ) -> CoreLocationGeofenceMonitor {
        let monitor = CoreLocationGeofenceMonitor(logger: SilentLogger())
        monitor.setOnTransition { identifier, transition, _, _, _, circle in
            onTransition(Delivered(identifier: identifier, transition: transition, circle: circle))
        }
        return monitor
    }

    private func coveringRegion(radius: Double = coveringRadius) -> CLCircularRegion {
        CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: Self.center.latitude, longitude: Self.center.longitude),
            radius: radius,
            identifier: Self.polygonId
        )
    }

    /// Must be `.circle`, not `.unknown`: `.unknown` makes the resolver write exit verdicts unchecked.
    @Test
    func coveringCircleEnter_expectTheCrossedCircleCarriedToTheResolver() {
        var delivered: [Delivered] = []
        let monitor = makeMonitor { delivered.append($0) }
        monitor.ownedRegionIdentifiers.insert(Self.polygonId)

        monitor.locationManager(CLLocationManager(), didEnterRegion: coveringRegion())

        #expect(delivered.count == 1)
        #expect(delivered.first?.transition == .enter)
        guard case .circle(let crossed) = delivered.first?.circle else {
            Issue.record("expected .circle, got \(String(describing: delivered.first?.circle))")
            return
        }
        #expect(abs(crossed.center.latitude - Self.center.latitude) < 0.00001)
        #expect(abs(crossed.center.longitude - Self.center.longitude) < 0.00001)
        #expect(crossed.radius == Self.coveringRadius)
    }

    /// Polygons register both edges whatever the customer asked for; membership needs the exit.
    @Test
    func coveringCircleExit_expectDeliveredWithItsCircle() {
        var delivered: [Delivered] = []
        let monitor = makeMonitor { delivered.append($0) }
        monitor.ownedRegionIdentifiers.insert(Self.polygonId)

        monitor.locationManager(CLLocationManager(), didExitRegion: coveringRegion())

        #expect(delivered.map(\.transition) == [.exit])
        if case .circle = delivered.first?.circle {} else {
            Issue.record("exit lost its circle: \(String(describing: delivered.first?.circle))")
        }
    }

    @Test
    func coveringCircleEnter_givenTheFenceIsReshapedBeforeDelivery_expectTheCrossedGeometry() async {
        var delivered: [Delivered] = []
        let monitor = CoreLocationGeofenceMonitor(logger: SilentLogger())
        monitor.ownedRegionIdentifiers.insert(Self.polygonId)

        // No handler yet, so the crossing buffers.
        monitor.locationManager(CLLocationManager(), didEnterRegion: coveringRegion())
        // A refresh reshapes the fence under the same id before the buffered event drains.
        monitor.locationManager(CLLocationManager(), didExitRegion: coveringRegion(radius: 900))
        monitor.setOnTransition { identifier, transition, _, _, _, circle in
            delivered.append(Delivered(identifier: identifier, transition: transition, circle: circle))
        }

        let drained = await waitForDrain { delivered.count >= 2 }
        #expect(drained, "buffered event never drained")
        guard case .circle(let crossed) = delivered.first?.circle else {
            Issue.record("expected .circle, got \(String(describing: delivered.first?.circle))")
            return
        }
        #expect(crossed.radius == Self.coveringRadius, "the enter reported a circle it did not cross")
        guard case .circle(let second) = delivered.last?.circle else {
            Issue.record("second event lost its circle")
            return
        }
        #expect(second.radius == 900, "each event must carry the circle IT crossed, not a shared lookup")
    }

    /// Yields, not spins: the drain needs the main actor this test holds.
    private func waitForDrain(iterations: Int = 200, _ condition: () -> Bool) async -> Bool {
        for _ in 0 ..< iterations {
            if condition() { return true }
            await Task.yield()
        }
        return condition()
    }

    @Test
    func ownedCrossing_expectAReceivedCallbackRecord() throws {
        try DiagnosticsGateTesting.withDiagnostics(true) {
            let logger = CapturingLogger()
            let monitor = CoreLocationGeofenceMonitor(logger: logger)
            monitor.setOnTransition { _, _, _, _, _, _ in }
            monitor.ownedRegionIdentifiers.insert(Self.polygonId)

            monitor.locationManager(CLLocationManager(), didEnterRegion: coveringRegion())

            #expect(logger.messages.contains { $0.contains("ev=os.callback.received") && $0.contains("id=\(Self.polygonId)") })
        }
    }
}
