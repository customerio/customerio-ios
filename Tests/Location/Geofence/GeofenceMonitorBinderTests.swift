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

    @Test
    func bind_expectTransitionHandlerInstalled() {
        let monitor = GeofenceRegionMonitoringMock()
        let tracker = makeTracker()

        GeofenceMonitorBinder.bind(monitor: monitor, tracker: tracker)

        #expect(monitor.setOnTransitionCallsCount == 1)
        // Binder no longer registers regions — that's the coordinator's job now.
        #expect(monitor.startMonitoringCalls.isEmpty)
    }

    /// Double-bind can happen when both `LocationModule.initialize` and
    /// `LocationModule.bootstrapForBackgroundDelivery` run in the same process.
    @Test
    func bind_givenCalledTwice_expectHandlerReinstalled() {
        let monitor = GeofenceRegionMonitoringMock()
        let tracker = makeTracker()

        GeofenceMonitorBinder.bind(monitor: monitor, tracker: tracker)
        GeofenceMonitorBinder.bind(monitor: monitor, tracker: tracker)

        #expect(monitor.setOnTransitionCallsCount == 2)
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
    var setOnAuthorizationChangedCallsCount = 0
    var lastAuthorizationChangedHandler: GeofenceAuthorizationChangedHandler?
    var startMonitoringCalls: [StartMonitoringCall] = []
    var stopMonitoringCalls: [String] = []
    var stopMonitoringAllCallsCount = 0
    var monitoredRegionIdentifiers: Set<String> = []

    func setOnTransition(_ handler: GeofenceTransitionHandler?) {
        setOnTransitionCallsCount += 1
    }

    func setOnAuthorizationChanged(_ handler: GeofenceAuthorizationChangedHandler?) {
        setOnAuthorizationChangedCallsCount += 1
        lastAuthorizationChangedHandler = handler
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
