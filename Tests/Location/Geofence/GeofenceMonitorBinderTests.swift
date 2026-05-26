@testable import CioInternalCommon
@testable import CioLocation
import Foundation
import SharedTests
import Testing

@Suite("GeofenceMonitorBinder")
@MainActor
struct GeofenceMonitorBinderTests {
    private func makeTracker() -> GeofenceEventTracker {
        let contextStore = BackgroundDeliveryContextStore(
            fileManager: .default,
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        let storage = GeofenceStorage(
            fileManager: .default,
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        return GeofenceEventTracker(
            storage: storage,
            pendingStore: PendingGeofenceMetricStore(),
            deliveryTracker: nil,
            contextStore: contextStore,
            eventBusHandler: EventBusHandlerMock(),
            dateUtil: DateUtilStub(),
            logger: LoggerMock()
        )
    }

    private func makeGeofence(id: String, radius: Double, transitions: Set<GeofenceTransition>) -> Geofence {
        Geofence(id: id, latitude: 1.0, longitude: 2.0, radius: radius, name: id, transitionTypes: transitions, lastUpdated: Date())
    }

    @Test
    func bind_givenGeofences_expectStartMonitoringForEach() {
        let geofences = [
            makeGeofence(id: "g1", radius: 100, transitions: [.enter]),
            makeGeofence(id: "g2", radius: 200, transitions: [.enter, .exit])
        ]
        let monitor = GeofenceRegionMonitoringMock()
        let tracker = makeTracker()

        GeofenceMonitorBinder.bind(monitor: monitor, geofences: geofences, tracker: tracker)

        #expect(monitor.setOnTransitionCallsCount == 1)
        #expect(monitor.startMonitoringCalls.count == 2)
        let identifiers = Set(monitor.startMonitoringCalls.map(\.identifier))
        #expect(identifiers == Set(["g1", "g2"]))
        let g1 = monitor.startMonitoringCalls.first { $0.identifier == "g1" }
        #expect(g1?.radius == 100)
        #expect(g1?.transitionTypes == [.enter])
        let g2 = monitor.startMonitoringCalls.first { $0.identifier == "g2" }
        #expect(g2?.transitionTypes == [.enter, .exit])
    }

    @Test
    func bind_givenEmpty_expectHandlerRegisteredAndNoMonitoring() {
        let monitor = GeofenceRegionMonitoringMock()
        let tracker = makeTracker()

        GeofenceMonitorBinder.bind(monitor: monitor, geofences: [], tracker: tracker)

        #expect(monitor.setOnTransitionCallsCount == 1)
        #expect(monitor.startMonitoringCalls.isEmpty)
    }
}

// MARK: - Mock

struct StartMonitoringCall: Equatable {
    let identifier: String
    let center: LocationData
    let radius: Double
    let transitionTypes: Set<GeofenceTransition>
}

@MainActor
final class GeofenceRegionMonitoringMock: GeofenceRegionMonitoring {
    var setOnTransitionCallsCount = 0
    var startMonitoringCalls: [StartMonitoringCall] = []
    var stopMonitoringCalls: [String] = []
    var stopMonitoringAllCallsCount = 0
    var monitoredRegionIdentifiers: Set<String> = []

    func setOnTransition(_ handler: GeofenceTransitionHandler?) {
        setOnTransitionCallsCount += 1
    }

    func startMonitoring(identifier: String, center: LocationData, radius: Double, transitionTypes: Set<GeofenceTransition>) {
        startMonitoringCalls.append(StartMonitoringCall(identifier: identifier, center: center, radius: radius, transitionTypes: transitionTypes))
        monitoredRegionIdentifiers.insert(identifier)
    }

    func stopMonitoring(identifier: String) {
        stopMonitoringCalls.append(identifier)
        monitoredRegionIdentifiers.remove(identifier)
    }

    func stopMonitoringAll() {
        stopMonitoringAllCallsCount += 1
        monitoredRegionIdentifiers.removeAll()
    }
}
