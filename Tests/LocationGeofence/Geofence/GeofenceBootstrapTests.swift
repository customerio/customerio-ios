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

    /// `maxBusinessGeofences == 0` is the server's kill switch.
    private static let killSwitchedConfig = GeofenceConfig(
        localRefreshTriggerRadius: 750,
        remoteFetchRefreshTriggerRadius: 3000,
        remoteFetchRefreshExpiry: 86400,
        duplicateEventsExpiry: 60,
        maxBusinessGeofences: 0,
        maxMonitoringDistance: GeofenceConstants.noMonitoringDistanceCap
    )

    // MARK: - Visit arming

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

    /// `bindVisits` can't cover this: it answers `true` for an identified user.
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

    /// Without the arm chain, an arm holding a pre-refresh config re-arms after the refresh's disarm.
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

        // The first read stalls holding the PRE-refresh config; later reads see the kill-switched one.
        let released = AsyncSignal()
        let reads = Synchronized<Int>(0)
        let killSwitched = Self.killSwitchedConfig
        GeofenceBootstrap.readCachedConfig = { graph in
            // Keyed on this graph: the seam is process-global and `GeofenceModuleSetupTests` reads it
            // concurrently.
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
        // Adopt is ruled out only because the OS holds nothing; expected-owned still names the trigger.
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
        let di = DIGraphShared.shared
        let storage = GeofenceStorage(
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        let retained = Geofence(
            id: "g1", latitude: 1, longitude: 2, radius: 100, name: nil,
            transitionTypes: [.exit], lastUpdated: Date(timeIntervalSince1970: 1),
            dwellThresholdSeconds: 60
        )
        let dropped = Geofence(
            id: "g2", latitude: 3, longitude: 4, radius: 100, name: nil,
            transitionTypes: [.exit], lastUpdated: Date(timeIntervalSince1970: 1),
            dwellThresholdSeconds: 60
        )
        await storage.setCachedGeofences([retained, dropped])
        await storage.recordRegistration(center: LocationData(latitude: 10, longitude: 20), businessIds: ["g1", "g2"])
        for geofence in [retained, dropped] {
            #expect(await storage.saveDwellVisit(
                GeofenceDwellVisit(
                    visitId: "visit-\(geofence.id)",
                    enteredAt: Date(timeIntervalSince1970: 100),
                    geometryRevision: geofence.dwellRevision,
                    userId: "user-1",
                    emitted: false
                ),
                geofenceId: geofence.id
            ))
        }
        di.override(value: storage, forType: GeofenceStorage.self)
        let contextStore = BackgroundDeliveryContextStore(
            fileManager: .default,
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        contextStore.setUserId("user-1")
        let dwellCoordinator = makeDwellCoordinator(storage: storage, contextStore: contextStore)
        di.override(value: dwellCoordinator, forType: GeofenceDwellCoordinator.self)
        let monitor = MockGeofenceRegionMonitor()
        monitor.osMonitoredRegions = ["g1", GeofenceConstants.movementTriggerIdentifier]
        di.override(value: monitor as GeofenceRegionMonitoring, forType: GeofenceRegionMonitoring.self)
        let coordinator = GeofenceSyncCoordinatorMock()
        di.override(value: coordinator as GeofenceSyncCoordinator, forType: GeofenceSyncCoordinator.self)
        defer { di.reset() }

        await GeofenceBootstrap.wireMonitor(di: di)
        // Continuity is reconciled off the run chain, so setup never waits on dwell storage.
        await GeofenceBootstrap.awaitPendingWorkForTesting()

        #expect(monitor.adoptExistingRegionsCallsCount == 0)
        #expect(coordinator.applyCachedRegistrationCallsCount == 1)
        #expect(await storage.getDwellVisit(geofenceId: "g1") != nil)
        #expect(await storage.getDwellVisit(geofenceId: "g2") == nil)
    }

    /// Dropping continuity for OS-dropped fences awaits storage. Doing that before registering let
    /// a sign-out queued after the identity check run first, so bootstrap registered for a user who
    /// had already signed out.
    @Test
    func wireMonitor_givenDroppedRegionsAndSignOutQueuedAfterBind_expectRegisteredBeforeSignOutRuns() async {
        let di = DIGraphShared.shared
        let storage = GeofenceStorage(
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        let dropped = Geofence(
            id: "g1", latitude: 1, longitude: 2, radius: 100, name: nil,
            transitionTypes: [.exit], lastUpdated: Date(timeIntervalSince1970: 1),
            dwellThresholdSeconds: 60
        )
        await storage.setCachedGeofences([dropped])
        await storage.recordRegistration(center: LocationData(latitude: 10, longitude: 20), businessIds: ["g1"])
        di.override(value: storage, forType: GeofenceStorage.self)
        let contextStore = BackgroundDeliveryContextStore(
            fileManager: .default,
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        contextStore.setUserId("user-1")
        di.override(value: contextStore, forType: BackgroundDeliveryContextStore.self)
        let dwellCoordinator = makeDwellCoordinator(storage: storage, contextStore: contextStore)
        di.override(value: dwellCoordinator, forType: GeofenceDwellCoordinator.self)
        let monitor = MockGeofenceRegionMonitor()
        // The OS kept nothing, so bootstrap takes the re-register branch with g1 missing.
        monitor.onSetOnTransition = {
            Task { @MainActor in contextStore.clearUserId() }
        }
        di.override(value: monitor as GeofenceRegionMonitoring, forType: GeofenceRegionMonitoring.self)
        let coordinator = GeofenceSyncCoordinatorMock()
        var userAtRegistration: String?
        coordinator.applyCachedRegistrationClosure = { _, _, _, _ in
            userAtRegistration = contextStore.currentUserId
            return nil
        }
        di.override(value: coordinator as GeofenceSyncCoordinator, forType: GeofenceSyncCoordinator.self)
        defer { di.reset() }

        await GeofenceBootstrap.wireMonitor(di: di)

        #expect(coordinator.applyCachedRegistrationCallsCount == 1)
        #expect(userAtRegistration == "user-1")
    }

    private func makeDwellCoordinator(
        storage: GeofenceStorage,
        contextStore: BackgroundDeliveryContextStore
    ) -> GeofenceDwellCoordinator {
        GeofenceDwellCoordinator(
            storage: storage,
            transitionEmitter: BootstrapTransitionEmitter(),
            contextStore: contextStore,
            logger: LoggerMock(),
            notificationCenter: NotificationCenter(),
            // Resumed deadlines must not reach CoreLocation from a unit test.
            freshFixProvider: { nil }
        )
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

/// Not a fixed sleep: a concurrent suite can hold the process-global run chain for seconds on CI.
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

private actor BootstrapTransitionEmitter: GeofenceTransitionEmitting {
    func trackTransition(geofenceId: String, transition: GeofenceTransition, occurredAt: Date) async {}
    func trackExit(
        geofenceId: String, occurredAt: Date, context: GeofenceExitContext?, expectedUserId: String?
    ) async {}

    func trackDwell(
        geofenceId: String, occurredAt: Date, context: GeofenceDwellContext, expectedUserId: String?
    ) async -> Bool {
        true
    }
}
