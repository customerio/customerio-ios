@testable import CioInternalCommon
@testable import CioLocation
import Foundation
import SharedTests
import Testing

@Suite("GeofenceBootstrap", .serialized)
@MainActor
struct GeofenceBootstrapTests {
    // MARK: - Discoverability log

    @Test
    func emitDiscoverabilityLog_givenNoCdpApiKey_expectInfoLogged() {
        let di = DIGraphShared.shared
        let store = BackgroundDeliveryContextStore(
            fileManager: .default,
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        di.override(value: store, forType: BackgroundDeliveryContextStore.self)
        let logger = LoggerMock()
        di.override(value: logger, forType: Logger.self)
        defer {
            di.reset()
        }

        GeofenceBootstrap.emitDiscoverabilityLogIfNeeded(di: di)

        #expect(logger.infoCallsCount == 1)
        let message = logger.infoReceivedArguments?.message ?? ""
        #expect(message.contains("allowBackgroundDelivery"))
    }

    @Test
    func emitDiscoverabilityLog_givenCdpApiKeyPersisted_expectNoLog() {
        let di = DIGraphShared.shared
        let store = BackgroundDeliveryContextStore(
            fileManager: .default,
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        store.setCdpApiKey("sk_test_abc")
        di.override(value: store, forType: BackgroundDeliveryContextStore.self)
        let logger = LoggerMock()
        di.override(value: logger, forType: Logger.self)
        defer {
            di.reset()
        }

        GeofenceBootstrap.emitDiscoverabilityLogIfNeeded(di: di)

        #expect(logger.infoCallsCount == 0)
    }

    // MARK: - DI singletons

    @Test
    func geofenceEventTracker_givenRepeatedResolution_expectSameInstance() {
        let di = DIGraphShared.shared
        let first = di.geofenceEventTracker
        let second = di.geofenceEventTracker
        #expect(first === second)
    }

    @Test
    func geofenceStorage_givenRepeatedResolution_expectSameInstance() {
        let di = DIGraphShared.shared
        let first = di.geofenceStorage
        let second = di.geofenceStorage
        #expect(first === second)
    }

    // MARK: - Self-heal on authorization change

    @Test
    func wireMonitor_givenInitialBind_expectAuthorizationHandlerInstalled() async {
        let di = DIGraphShared.shared
        let storage = GeofenceStorage(
            fileManager: .default,
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        di.override(value: storage, forType: GeofenceStorage.self)
        let monitor = GeofenceRegionMonitoringMock()
        di.override(value: monitor as GeofenceRegionMonitoring, forType: GeofenceRegionMonitoring.self)
        defer { di.reset() }

        await GeofenceBootstrap.wireMonitor(di: di)

        #expect(monitor.setOnAuthorizationChangedCallsCount == 1)
        #expect(monitor.lastAuthorizationChangedHandler != nil)
    }

    @Test
    func wireMonitor_givenAuthorizationFires_expectReRegistration() async {
        let di = DIGraphShared.shared
        let storage = GeofenceStorage(
            fileManager: .default,
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        let geofence = Geofence(
            id: "g1", latitude: 1.0, longitude: 2.0, radius: 100,
            name: "g1", transitionTypes: [.enter], lastUpdated: Date()
        )
        await storage.setCachedGeofences([geofence])
        di.override(value: storage, forType: GeofenceStorage.self)
        let monitor = GeofenceRegionMonitoringMock()
        di.override(value: monitor as GeofenceRegionMonitoring, forType: GeofenceRegionMonitoring.self)
        defer { di.reset() }

        await GeofenceBootstrap.wireMonitor(di: di)
        #expect(monitor.startMonitoringCalls.count == 1)

        // Simulate iOS reporting a permission change. The handler spawns a Task to re-run
        // wireMonitor; the sleep gives that Task time to schedule and complete.
        monitor.lastAuthorizationChangedHandler?()
        try? await Task.sleep(nanoseconds: 100000000)

        #expect(monitor.startMonitoringCalls.count == 2)
    }

    @Test
    func emitDiscoverabilityLog_givenProviderReturnsKey_expectNoLog() {
        let di = DIGraphShared.shared
        let store = BackgroundDeliveryContextStore(
            fileManager: .default,
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        let provider = StubProvider(value: "live_key")
        store.setCdpApiKeyProvider(provider)
        di.override(value: store, forType: BackgroundDeliveryContextStore.self)
        let logger = LoggerMock()
        di.override(value: logger, forType: Logger.self)
        defer {
            di.reset()
            _ = provider // keep alive until reset
        }

        GeofenceBootstrap.emitDiscoverabilityLogIfNeeded(di: di)

        #expect(logger.infoCallsCount == 0)
    }
}

private final class StubProvider: BackgroundDeliveryCdpApiKeyProvider {
    let value: String?
    init(value: String?) { self.value = value }
    var cdpApiKey: String? { value }
}
