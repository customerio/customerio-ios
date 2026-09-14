@testable import CioInternalCommon
@testable import CioLocationGeofence
import CoreLocation
import Foundation
import Testing

/// iOS 13–17 run the classic monitor, and a polygon reaches it as its covering circle. The
/// membership verdict is the resolver's job, but it can only be right if this path hands over the
/// circle the OS actually crossed — a polygon forwarded as `unknown`, or carrying a replacement
/// fence's geometry, silently becomes a circle fence for every pre-iOS-18 user.
///
/// Measured on the iOS 17.5 simulator 2026-09-14: the classic path already fetches, registers and
/// evaluates polygons end-to-end. These pin the monitor's half of that so it cannot regress
/// unnoticed — no drive covers this band, and the CLMonitor twin cannot be built in a test at all.
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

    /// A polygon's covering circle must arrive as `.circle`, never `.unknown`: the resolver's exit
    /// branch writes `outside` only when it can check the crossed circle is still the fence's, and
    /// `unknown` makes it write that verdict unchecked.
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

    /// Both edges must reach the resolver. A polygon is registered with `[.enter, .exit]` whatever
    /// the customer asked for, because membership needs the filtered edge to advance — dropping
    /// the exit here would leave a polygon entered and never left.
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

    /// The circle is captured from the region the OS raised the event against, not looked up when
    /// the event is delivered. A refresh replacing the fence under the same id between the crossing
    /// and the drain must not make the old crossing describe the new geometry.
    @Test
    func coveringCircleEnter_givenTheFenceIsReshapedBeforeDelivery_expectTheCrossedGeometry() async {
        var delivered: [Delivered] = []
        let monitor = CoreLocationGeofenceMonitor(logger: SilentLogger())
        monitor.ownedRegionIdentifiers.insert(Self.polygonId)

        // No handler bound yet, so the crossing buffers — the cold-wake ordering.
        monitor.locationManager(CLLocationManager(), didEnterRegion: coveringRegion())
        // A refresh reshapes the fence under the same id before the buffered event drains.
        monitor.locationManager(CLLocationManager(), didExitRegion: coveringRegion(radius: 900))
        monitor.setOnTransition { identifier, transition, _, _, _, circle in
            delivered.append(Delivered(identifier: identifier, transition: transition, circle: circle))
        }

        // The drain is a Task hop; give it one turn of the main actor.
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

    /// Yields the main actor until the drain has run, rather than sleeping a fixed interval — a
    /// fixed wait is the shape that made the MessagingInApp suite flaky. It must yield rather than
    /// spin: the drain is a `Task { @MainActor }`, so a synchronous loop holds the actor the drain
    /// needs and the condition can never become true.
    private func waitForDrain(iterations: Int = 200, _ condition: () -> Bool) async -> Bool {
        for _ in 0 ..< iterations {
            if condition() { return true }
            await Task.yield()
        }
        return condition()
    }

    /// The gate analysis for iOS 13-17 rests on "registering 9 regions produced ZERO
    /// `os.callback.received`", which is only evidence if this path emits that record at all. An
    /// owned crossing must produce one — see the absence-of-a-log-line trap.
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
