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
    func wireMonitor_givenInitialBind_expectTransitionHandlerAndCoordinatorApplyAndAuthHandler() async {
        let di = DIGraphShared.shared
        let monitor = MockGeofenceRegionMonitor()
        di.override(value: monitor as GeofenceRegionMonitoring, forType: GeofenceRegionMonitoring.self)
        let coordinator = GeofenceSyncCoordinatorMock()
        di.override(value: coordinator as GeofenceSyncCoordinator, forType: GeofenceSyncCoordinator.self)
        defer { di.reset() }

        await GeofenceBootstrap.wireMonitor(di: di)

        #expect(monitor.setOnTransitionCallsCount == 1)
        #expect(coordinator.applyCachedRegistrationCallsCount == 1)
        #expect(monitor.setOnAuthorizationChangedCallsCount == 1)
        #expect(monitor.onAuthorizationChanged != nil)
    }

    @Test
    func wireMonitor_givenCachedRegions_expectPipedToCoordinatorApply() async {
        let di = DIGraphShared.shared
        let storage = GeofenceStorage(
            fileManager: .default,
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        await storage.setCachedGeofences([
            Geofence(
                id: "g1",
                latitude: 1,
                longitude: 2,
                radius: 100,
                name: "g1",
                transitionTypes: [.enter],
                lastUpdated: Date(timeIntervalSince1970: 0)
            )
        ])
        di.override(value: storage, forType: GeofenceStorage.self)
        let monitor = MockGeofenceRegionMonitor()
        di.override(value: monitor as GeofenceRegionMonitoring, forType: GeofenceRegionMonitoring.self)
        let coordinator = GeofenceSyncCoordinatorMock()
        di.override(value: coordinator as GeofenceSyncCoordinator, forType: GeofenceSyncCoordinator.self)
        defer { di.reset() }

        await GeofenceBootstrap.wireMonitor(di: di)

        #expect(coordinator.applyCachedRegistrationReceivedArguments?.cachedRegions.map(\.id) == ["g1"])
    }

    @Test
    func geofenceSyncCoordinator_givenRepeatedResolution_expectSameInstance() {
        let di = DIGraphShared.shared
        let first = di.geofenceSyncCoordinator as? GeofenceSyncCoordinatorImpl
        let second = di.geofenceSyncCoordinator as? GeofenceSyncCoordinatorImpl
        // Singleton-ness is load-bearing: the instance-level `refreshInProgress` dedup
        // gate only deduplicates if every caller resolves to the same instance.
        #expect(first === second)
    }

    @Test
    func wireMonitor_givenAuthorizationFires_expectApplyCachedRegistrationRerun() async {
        let di = DIGraphShared.shared
        let monitor = MockGeofenceRegionMonitor()
        di.override(value: monitor as GeofenceRegionMonitoring, forType: GeofenceRegionMonitoring.self)
        let coordinator = GeofenceSyncCoordinatorMock()
        di.override(value: coordinator as GeofenceSyncCoordinator, forType: GeofenceSyncCoordinator.self)
        defer { di.reset() }

        await GeofenceBootstrap.wireMonitor(di: di)
        #expect(coordinator.applyCachedRegistrationCallsCount == 1)

        // Simulate iOS reporting a permission change. The handler spawns a Task to re-run
        // wireMonitor; the sleep gives that Task time to schedule and complete.
        monitor.onAuthorizationChanged?()
        try? await Task.sleep(nanoseconds: 100000000)

        #expect(coordinator.applyCachedRegistrationCallsCount == 2)
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
