@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioLocationGeofence
@testable import CioLocationGeofenceMocks
import Foundation
import SharedTests
import Testing

// Nested for serialization only; top-level indentation is kept so `git blame` stays useful.
// swiftformat:disable indent
extension SharedDIGraphSuites {
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

    /// `maxBusinessGeofences == 0` — the server turning geofence registration off.
    private static let killSwitchedConfig = GeofenceConfig(
        localRefreshTriggerRadius: 750,
        remoteFetchRefreshTriggerRadius: 3000,
        remoteFetchRefreshExpiry: 86400,
        duplicateEventsExpiry: 60,
        maxBusinessGeofences: 0,
        maxMonitoringDistance: GeofenceConstants.noMonitoringDistanceCap
    )

    // MARK: - Visit arming

    /// Setup runs before the host calls `identify`, so arming must work on demand, not only at
    /// launch.
    @Test
    func armVisitMonitoring_givenIdentifiedUser_expectStarted() {
        let di = DIGraphShared.shared
        let store = BackgroundDeliveryContextStore(
            fileManager: .default,
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        store.setUserId("user-1")
        di.override(value: store, forType: BackgroundDeliveryContextStore.self)
        let visitMonitor = MockGeofenceVisitMonitor()
        di.override(value: visitMonitor as GeofenceVisitMonitoring, forType: GeofenceVisitMonitoring.self)
        defer { di.reset() }

        GeofenceBootstrap.armVisitMonitoring(di: di, config: nil)

        #expect(visitMonitor.startCallCount == 1)
        #expect(visitMonitor.stopCallCount == 0)
    }

    /// A visit waking a signed-out process evaluates an empty set, so sign-out must disarm.
    @Test
    func armVisitMonitoring_givenNoIdentifiedUser_expectStopped() {
        let di = DIGraphShared.shared
        let store = BackgroundDeliveryContextStore(
            fileManager: .default,
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        di.override(value: store, forType: BackgroundDeliveryContextStore.self)
        let visitMonitor = MockGeofenceVisitMonitor()
        di.override(value: visitMonitor as GeofenceVisitMonitoring, forType: GeofenceVisitMonitoring.self)
        defer { di.reset() }

        GeofenceBootstrap.armVisitMonitoring(di: di, config: nil)

        #expect(visitMonitor.startCallCount == 0)
        #expect(visitMonitor.stopCallCount == 1)
    }

    /// A kill-switched account registers nothing, so a visit would wake the process to evaluate
    /// an empty set. `bindVisits` cannot close this — it answers `true` for an identified user.
    @Test
    func armVisitMonitoring_givenRegistrationKillSwitched_expectStopped() {
        let di = DIGraphShared.shared
        let store = BackgroundDeliveryContextStore(
            fileManager: .default,
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        store.setUserId("user-1")
        di.override(value: store, forType: BackgroundDeliveryContextStore.self)
        let visitMonitor = MockGeofenceVisitMonitor()
        di.override(value: visitMonitor as GeofenceVisitMonitoring, forType: GeofenceVisitMonitoring.self)
        defer { di.reset() }

        GeofenceBootstrap.armVisitMonitoring(di: di, config: Self.killSwitchedConfig)

        #expect(visitMonitor.startCallCount == 0)
        #expect(visitMonitor.stopCallCount == 1)
    }

    /// A config that allows registration still arms: the gate is the kill switch, not the presence
    /// of a config.
    @Test
    func armVisitMonitoring_givenRegistrationEnabled_expectStarted() {
        let di = DIGraphShared.shared
        let store = BackgroundDeliveryContextStore(
            fileManager: .default,
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        store.setUserId("user-1")
        di.override(value: store, forType: BackgroundDeliveryContextStore.self)
        let visitMonitor = MockGeofenceVisitMonitor()
        di.override(value: visitMonitor as GeofenceVisitMonitoring, forType: GeofenceVisitMonitoring.self)
        defer { di.reset() }

        GeofenceBootstrap.armVisitMonitoring(di: di, config: .fallback)

        #expect(visitMonitor.startCallCount == 1)
        #expect(visitMonitor.stopCallCount == 0)
    }

    /// The config read is a suspension point, so without the arm chain an arm that read a
    /// pre-refresh config resumes after the refresh's disarm and re-arms a kill-switched account.
    ///
    /// Asserts on the last call: both orderings produce one start and one stop.
    @Test
    func armVisitMonitoring_givenTwoArmsRace_expectTheLaterConfigToWin() async {
        let di = DIGraphShared.shared
        let store = BackgroundDeliveryContextStore(
            fileManager: .default,
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        store.setUserId("user-1")
        di.override(value: store, forType: BackgroundDeliveryContextStore.self)
        let visitMonitor = MockGeofenceVisitMonitor()
        di.override(value: visitMonitor as GeofenceVisitMonitoring, forType: GeofenceVisitMonitoring.self)
        let realRead = GeofenceBootstrap.readCachedConfig
        defer {
            GeofenceBootstrap.readCachedConfig = realRead
            di.reset()
        }

        // The first read stalls holding the PRE-refresh config; every later read sees the
        // kill-switched one the refresh landed meanwhile.
        let released = AsyncSignal()
        let reads = Synchronized<Int>(0)
        let killSwitched = Self.killSwitchedConfig
        GeofenceBootstrap.readCachedConfig = { graph in
            // Keyed on this graph: the seam is process-global, and `GeofenceModuleSetupTests` (not
            // under `SharedDIGraphSuites`) reads it from its own `DIGraphShared()` concurrently.
            guard graph === di else { return await realRead(graph) }
            let isFirst = reads.mutating { count in
                count += 1
                return count == 1
            }
            guard isFirst else { return killSwitched }
            await released.wait()
            return .fallback
        }

        async let first: Void = GeofenceBootstrap.armVisitMonitoring(di: di)
        async let second: Void = GeofenceBootstrap.armVisitMonitoring(di: di)
        await released.fire()
        _ = await(first, second)

        #expect(visitMonitor.calls.last == .stop)
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
        // First launch: expected-owned still names the movement trigger, so adopt is ruled out
        // only because the OS holds nothing.
        #expect(monitor.adoptExistingRegionsCallsCount == 0)
        #expect(monitor.setOnAuthorizationChangedCallsCount == 1)
        #expect(monitor.onAuthorizationChanged != nil)
        #expect(monitor.reportPermissionTierCallsCount == 1)
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
        // A local re-rank moved the registration center past the fetch anchor; restoring from the
        // fetch anchor would revert to the older nearest-set.
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
        // Persisted as the ranking-staleness reference, so a later refresh measures distance from
        // the set actually registered.
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

    // MARK: - Adopt OS-persisted regions

    @Test
    func wireMonitor_givenOsStillMonitorsOurRegions_expectAdoptedWithoutReregistering() async {
        // Relaunch with the OS still holding last session's regions: re-claim them and leave the
        // persisted registration center untouched.
        let di = DIGraphShared.shared
        let storage = GeofenceStorage(
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
        await storage.recordRegistration(center: LocationData(latitude: 10, longitude: 20), businessIds: ["g1"])
        di.override(value: storage, forType: GeofenceStorage.self)
        let monitor = MockGeofenceRegionMonitor()
        monitor.osMonitoredRegions = ["g1", GeofenceConstants.movementTriggerIdentifier]
        di.override(value: monitor as GeofenceRegionMonitoring, forType: GeofenceRegionMonitoring.self)
        let coordinator = GeofenceSyncCoordinatorMock()
        di.override(value: coordinator as GeofenceSyncCoordinator, forType: GeofenceSyncCoordinator.self)
        defer { di.reset() }

        await GeofenceBootstrap.wireMonitor(di: di)

        #expect(monitor.adoptExistingRegionsCallsCount == 1)
        #expect(monitor.adoptedIdentifiers == ["g1", GeofenceConstants.movementTriggerIdentifier])
        #expect(coordinator.applyCachedRegistrationCallsCount == 0)
        #expect(await storage.getLastRegistrationCenter() == LocationData(latitude: 10, longitude: 20))
        #expect(monitor.reportPermissionTierCallsCount == 1)
    }

    @Test
    func wireMonitor_givenAdoptPath_expectPersistedMonitorRecordsHandedToAdopt() async {
        // The CLMonitor path seeds geometry from these records at adopt, so a sync landing before
        // the queued re-arm drains reads carried-over regions as unchanged.
        let di = DIGraphShared.shared
        let storage = GeofenceStorage(
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
        await storage.recordRegistration(center: LocationData(latitude: 10, longitude: 20), businessIds: ["g1"])
        await storage.recordMonitorRegistration(
            identifier: "g1",
            transitionTypes: [.enter],
            initialState: .exit,
            center: LocationData(latitude: 1, longitude: 2),
            radius: 100
        )
        di.override(value: storage, forType: GeofenceStorage.self)
        let monitor = MockGeofenceRegionMonitor()
        monitor.osMonitoredRegions = ["g1", GeofenceConstants.movementTriggerIdentifier]
        di.override(value: monitor as GeofenceRegionMonitoring, forType: GeofenceRegionMonitoring.self)
        let coordinator = GeofenceSyncCoordinatorMock()
        di.override(value: coordinator as GeofenceSyncCoordinator, forType: GeofenceSyncCoordinator.self)
        defer { di.reset() }

        await GeofenceBootstrap.wireMonitor(di: di)

        #expect(monitor.adoptExistingRegionsCallsCount == 1)
        let record = monitor.adoptedRecords["g1"]
        #expect(record?.center == LocationData(latitude: 1, longitude: 2))
        #expect(record?.radius == 100)
        #expect(record?.lastState == .exit)
    }

    @Test
    func wireMonitor_givenOsAlsoMonitorsHostAppRegions_expectOnlyOwnRegionsAdopted() async {
        // `CLLocationManager.monitoredRegions` is app-wide, so adoption must never claim the host
        // app's regions.
        let di = DIGraphShared.shared
        let storage = GeofenceStorage(
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
        await storage.recordRegistration(center: LocationData(latitude: 10, longitude: 20), businessIds: ["g1"])
        di.override(value: storage, forType: GeofenceStorage.self)
        let monitor = MockGeofenceRegionMonitor()
        monitor.osMonitoredRegions = ["g1", GeofenceConstants.movementTriggerIdentifier, "host.app.region"]
        di.override(value: monitor as GeofenceRegionMonitoring, forType: GeofenceRegionMonitoring.self)
        let coordinator = GeofenceSyncCoordinatorMock()
        di.override(value: coordinator as GeofenceSyncCoordinator, forType: GeofenceSyncCoordinator.self)
        defer { di.reset() }

        await GeofenceBootstrap.wireMonitor(di: di)

        #expect(monitor.adoptedIdentifiers == ["g1", GeofenceConstants.movementTriggerIdentifier])
        #expect(coordinator.applyCachedRegistrationCallsCount == 0)
    }

    @Test
    func wireMonitor_givenOnlyMovementTriggerRegistered_expectTriggerAdopted() async {
        // Relaunch after an empty nearby response: only the trigger is held. Unadopted, its EXIT is
        // dropped at the ownership filter and the refresh decision skips (fresh cache, no
        // movement), leaving the device dark until the cache ages out.
        let di = DIGraphShared.shared
        let storage = GeofenceStorage(
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        await storage.recordRegistration(center: LocationData(latitude: 10, longitude: 20), businessIds: [])
        di.override(value: storage, forType: GeofenceStorage.self)
        let monitor = MockGeofenceRegionMonitor()
        monitor.osMonitoredRegions = [GeofenceConstants.movementTriggerIdentifier]
        di.override(value: monitor as GeofenceRegionMonitoring, forType: GeofenceRegionMonitoring.self)
        let coordinator = GeofenceSyncCoordinatorMock()
        di.override(value: coordinator as GeofenceSyncCoordinator, forType: GeofenceSyncCoordinator.self)
        defer { di.reset() }

        await GeofenceBootstrap.wireMonitor(di: di)

        #expect(monitor.adoptedIdentifiers == [GeofenceConstants.movementTriggerIdentifier])
        #expect(coordinator.applyCachedRegistrationCallsCount == 0)
    }

    @Test
    func wireMonitor_givenKillSwitchedConfig_expectTriggerNotAdopted() async {
        // Expected-owned mirrors the register condition: under the kill switch the trigger is not
        // registered, so it is not reclaimed.
        let di = DIGraphShared.shared
        let storage = GeofenceStorage(
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        await storage.setCachedConfig(GeofenceConfig(
            localRefreshTriggerRadius: 750,
            remoteFetchRefreshTriggerRadius: 3000,
            remoteFetchRefreshExpiry: 86400,
            duplicateEventsExpiry: 60,
            maxBusinessGeofences: 0,
            maxMonitoringDistance: GeofenceConstants.noMonitoringDistanceCap
        ))
        await storage.recordRegistration(center: LocationData(latitude: 10, longitude: 20), businessIds: [])
        di.override(value: storage, forType: GeofenceStorage.self)
        let monitor = MockGeofenceRegionMonitor()
        monitor.osMonitoredRegions = [GeofenceConstants.movementTriggerIdentifier]
        di.override(value: monitor as GeofenceRegionMonitoring, forType: GeofenceRegionMonitoring.self)
        let coordinator = GeofenceSyncCoordinatorMock()
        di.override(value: coordinator as GeofenceSyncCoordinator, forType: GeofenceSyncCoordinator.self)
        defer { di.reset() }

        await GeofenceBootstrap.wireMonitor(di: di)

        #expect(monitor.adoptExistingRegionsCallsCount == 0)
    }

    @Test
    func wireMonitor_givenOsRetainedOnlyASubset_expectReregisterNotPartialAdopt() async {
        // Partial drop: adopting the subset would leave g2 unmonitored, so re-register from cache.
        let di = DIGraphShared.shared
        let storage = GeofenceStorage(
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        await storage.recordRegistration(center: LocationData(latitude: 10, longitude: 20), businessIds: ["g1", "g2"])
        di.override(value: storage, forType: GeofenceStorage.self)
        let monitor = MockGeofenceRegionMonitor()
        monitor.osMonitoredRegions = ["g1", GeofenceConstants.movementTriggerIdentifier]
        di.override(value: monitor as GeofenceRegionMonitoring, forType: GeofenceRegionMonitoring.self)
        let coordinator = GeofenceSyncCoordinatorMock()
        di.override(value: coordinator as GeofenceSyncCoordinator, forType: GeofenceSyncCoordinator.self)
        defer { di.reset() }

        await GeofenceBootstrap.wireMonitor(di: di)

        #expect(monitor.adoptExistingRegionsCallsCount == 0)
        #expect(coordinator.applyCachedRegistrationCallsCount == 1)
    }

    @Test
    func geofenceSyncCoordinator_givenRepeatedResolution_expectSameInstance() {
        let di = DIGraphShared.shared
        let first = di.geofenceSyncCoordinator as? GeofenceSyncCoordinatorImpl
        let second = di.geofenceSyncCoordinator as? GeofenceSyncCoordinatorImpl
        // The instance-level in-flight gate only deduplicates if every caller shares one instance.
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

        monitor.onAuthorizationChanged?()

        await awaitRerun { coordinator.applyCachedRegistrationCallsCount == 2 }
    }

    @Test
    func wireMonitor_givenReconciliationFires_expectRerunAgainstLiveOsSet() async {
        let di = DIGraphShared.shared
        let monitor = MockGeofenceRegionMonitor()
        di.override(value: monitor as GeofenceRegionMonitoring, forType: GeofenceRegionMonitoring.self)
        let coordinator = GeofenceSyncCoordinatorMock()
        di.override(value: coordinator as GeofenceSyncCoordinator, forType: GeofenceSyncCoordinator.self)
        defer { di.reset() }

        await GeofenceBootstrap.wireMonitor(di: di)
        #expect(monitor.setOnReconciledCallsCount == 1)
        #expect(coordinator.applyCachedRegistrationCallsCount == 1)

        // The CLMonitor path fires this after reconciling its mirror against the OS's live set.
        monitor.onReconciled?()

        await awaitRerun { coordinator.applyCachedRegistrationCallsCount == 2 }
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
}

// swiftformat:enable indent

/// Waits for a re-run the handler spawned onto the process-global run chain. A fixed sleep races
/// whatever else holds that chain, which a concurrent suite can hold for seconds on CI.
private func awaitRerun(
    _ condition: () -> Bool,
    within: TimeInterval = 10,
    sourceLocation: SourceLocation = #_sourceLocation
) async {
    let deadline = Date().addingTimeInterval(within)
    while Date() < deadline {
        await GeofenceBootstrap.awaitPendingWorkForTesting()
        if condition() { return }
        try? await Task.sleep(nanoseconds: 5000000)
    }
    Issue.record("condition not met within \(within)s", sourceLocation: sourceLocation)
}

private actor AsyncSignal {
    private var continuation: CheckedContinuation<Void, Never>?
    private var fired = false

    func wait() async {
        if fired { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func fire() {
        fired = true
        continuation?.resume()
        continuation = nil
    }
}
