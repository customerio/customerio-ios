@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioLocationGeofence
@testable import CioLocationGeofenceMocks
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
    func wireMonitor_givenRegistrationCenterAndLastSync_expectAnchorFromRegistrationCenter() async {
        // A local re-rank moved the registration center past the fetch anchor. Restore must use
        // the registration center so cold boot reproduces the last-monitored set, not the older one.
        let di = DIGraphShared.shared
        let storage = GeofenceStorage(
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        await storage.recordSync(timestamp: Date(), location: LocationData(latitude: 0, longitude: 0))
        await storage.recordRegistration(center: LocationData(latitude: 10, longitude: 20), businessIds: ["g1"])
        di.override(value: storage, forType: GeofenceStorage.self)
        let monitor = MockGeofenceRegionMonitor()
        di.override(value: monitor as GeofenceRegionMonitoring, forType: GeofenceRegionMonitoring.self)
        let coordinator = GeofenceSyncCoordinatorMock()
        di.override(value: coordinator as GeofenceSyncCoordinator, forType: GeofenceSyncCoordinator.self)
        defer { di.reset() }

        await GeofenceBootstrap.wireMonitor(di: di)

        let anchor = coordinator.applyCachedRegistrationReceivedArguments?.anchor
        #expect(anchor?.latitude == 10)
        #expect(anchor?.longitude == 20)
    }

    @Test
    func wireMonitor_givenNoRegistrationCenter_expectAnchorFromLastSync() async {
        // First restore after a remote fetch (no local re-rank yet): fall back to the fetch anchor.
        let di = DIGraphShared.shared
        let storage = GeofenceStorage(
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        await storage.recordSync(timestamp: Date(), location: LocationData(latitude: 5, longitude: 6))
        di.override(value: storage, forType: GeofenceStorage.self)
        let monitor = MockGeofenceRegionMonitor()
        di.override(value: monitor as GeofenceRegionMonitoring, forType: GeofenceRegionMonitoring.self)
        let coordinator = GeofenceSyncCoordinatorMock()
        di.override(value: coordinator as GeofenceSyncCoordinator, forType: GeofenceSyncCoordinator.self)
        defer { di.reset() }

        await GeofenceBootstrap.wireMonitor(di: di)

        let anchor = coordinator.applyCachedRegistrationReceivedArguments?.anchor
        #expect(anchor?.latitude == 5)
        #expect(anchor?.longitude == 6)
    }

    @Test
    func wireMonitor_givenCoordinatorReturnsRegistration_expectPersistedAsReference() async {
        // The registration applyCachedRegistration reports is persisted as the ranking-staleness
        // reference so a later refresh measures distance from the actually-registered set.
        let di = DIGraphShared.shared
        let storage = GeofenceStorage(
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        di.override(value: storage, forType: GeofenceStorage.self)
        let monitor = MockGeofenceRegionMonitor()
        di.override(value: monitor as GeofenceRegionMonitoring, forType: GeofenceRegionMonitoring.self)
        let coordinator = GeofenceSyncCoordinatorMock()
        coordinator.applyCachedRegistrationReturnValue = GeofenceRegistration(
            center: LocationData(latitude: 12, longitude: 34),
            businessIds: ["g1"]
        )
        di.override(value: coordinator as GeofenceSyncCoordinator, forType: GeofenceSyncCoordinator.self)
        defer { di.reset() }

        await GeofenceBootstrap.wireMonitor(di: di)

        let persisted = await storage.getLastRegistrationCenter()
        #expect(persisted == LocationData(latitude: 12, longitude: 34))
        #expect(await storage.getRegisteredBusinessIds() == ["g1"])
    }

    @Test
    func wireMonitor_givenCoordinatorReturnsNil_expectNoRegistrationPersisted() async {
        let di = DIGraphShared.shared
        let storage = GeofenceStorage(
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        di.override(value: storage, forType: GeofenceStorage.self)
        let monitor = MockGeofenceRegionMonitor()
        di.override(value: monitor as GeofenceRegionMonitoring, forType: GeofenceRegionMonitoring.self)
        let coordinator = GeofenceSyncCoordinatorMock()
        coordinator.applyCachedRegistrationReturnValue = nil
        di.override(value: coordinator as GeofenceSyncCoordinator, forType: GeofenceSyncCoordinator.self)
        defer { di.reset() }

        await GeofenceBootstrap.wireMonitor(di: di)

        #expect(await storage.getLastRegistrationCenter() == nil)
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
    init(value: String?) {
        self.value = value
    }

    var cdpApiKey: String? { value }
}
