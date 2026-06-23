@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioLocationGeofence
@testable import CioLocationGeofenceMocks
import Foundation
import SharedTests
import Testing

@Suite("GeofenceSyncCoordinator", .serialized)
@MainActor
struct GeofenceSyncCoordinatorTests {
    // MARK: - Fixtures

    private func makeContextStore(userId: String? = "user-1") -> BackgroundDeliveryContextStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = BackgroundDeliveryContextStore(fileManager: .default, directoryURL: dir)
        if let userId { store.setUserId(userId) }
        return store
    }

    private func makeStorage() -> GeofenceStorage {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return GeofenceStorage(directoryURL: dir)
    }

    private struct Setup {
        let coordinator: GeofenceSyncCoordinatorImpl
        let api: GeofenceApiServiceMock
        let monitor: MockGeofenceRegionMonitor
        let contextStore: BackgroundDeliveryContextStore
        let dateUtil: DateUtilStub
    }

    private func makeCoordinator(
        api: GeofenceApiServiceMock = GeofenceApiServiceMock(),
        storage: GeofenceSyncStorage,
        monitor: MockGeofenceRegionMonitor? = nil,
        contextStore: BackgroundDeliveryContextStore? = nil,
        dateUtil: DateUtilStub = DateUtilStub(),
        syncMode: GeofenceSyncMode = .fetchAll
    ) -> Setup {
        let resolvedContextStore = contextStore ?? makeContextStore()
        let resolvedMonitor = monitor ?? MockGeofenceRegionMonitor()
        let coordinator = GeofenceSyncCoordinatorImpl(
            apiService: api,
            storage: storage,
            monitor: resolvedMonitor,
            contextStore: resolvedContextStore,
            dateUtil: dateUtil,
            logger: LoggerMock(),
            syncMode: syncMode
        )
        return Setup(
            coordinator: coordinator,
            api: api,
            monitor: resolvedMonitor,
            contextStore: resolvedContextStore,
            dateUtil: dateUtil
        )
    }

    private func makeRegion(id: String, latitude: Double, longitude: Double, radius: Double = 100) -> Geofence {
        Geofence(
            id: id,
            latitude: latitude,
            longitude: longitude,
            radius: radius,
            name: id,
            transitionTypes: [.enter, .exit],
            lastUpdated: Date(timeIntervalSince1970: 1700000000)
        )
    }

    private func makeApiResponse(
        regions: [Geofence] = [],
        config: GeofenceConfig? = nil
    ) -> GeofenceApiResponse {
        let apiRegions = regions.map { region in
            GeofenceApiRegion(
                id: region.id,
                name: region.name,
                latitude: region.latitude,
                longitude: region.longitude,
                radius: region.radius,
                externalId: nil,
                transitionTypes: region.transitionTypes.map(\.rawValue),
                lastUpdated: region.lastUpdated.timeIntervalSince1970
            )
        }
        let apiConfig = config.map { config in
            GeofenceApiConfig(
                localRefreshTriggerRadius: config.localRefreshTriggerRadius,
                remoteFetchRefreshTriggerRadius: config.remoteFetchRefreshTriggerRadius,
                // GeofenceConfig stores seconds; wire format is ms — convert back so the
                // parse boundary's ms→s logic produces the same seconds.
                remoteFetchRefreshExpiryTime: config.remoteFetchRefreshExpiry * 1000,
                duplicateEventsExpiryTime: config.duplicateEventsExpiry * 1000,
                maxMonitoringDistance: config.maxMonitoringDistance,
                ios: GeofenceApiPlatformConfig(maxBusinessGeofences: config.maxBusinessGeofences)
            )
        }
        return GeofenceApiResponse(config: apiConfig, geofences: apiRegions)
    }

    // MARK: - Guards

    @Test
    func refresh_givenNoUserId_expectFailureAndNoApiCall() async {
        let storage = makeStorage()
        let setup = makeCoordinator(storage: storage, contextStore: makeContextStore(userId: nil))

        let result = await setup.coordinator.refresh(latitude: 1.0, longitude: 2.0)

        #expect(result.errorOrNil == .noIdentifiedUser)
        #expect(setup.api.fetchAllGeofencesCallsCount == 0)
        #expect(setup.monitor.startedRegions.isEmpty)
    }

    @Test
    func refresh_givenFreshLastSync_expectSkipApiCallAndReturnSuccess() async {
        let storage = makeStorage()
        let dateUtil = DateUtilStub()
        // Record a sync 100s ago + config with 1-hour expiry → still fresh.
        let oneHour: TimeInterval = 60 * 60
        await storage.setCachedConfig(GeofenceConfig(
            localRefreshTriggerRadius: 1000,
            remoteFetchRefreshTriggerRadius: 3000,
            remoteFetchRefreshExpiry: oneHour,
            duplicateEventsExpiry: 60,
            maxBusinessGeofences: 10,
            maxMonitoringDistance: GeofenceConstants.noMonitoringDistanceCap
        ))
        await storage.recordSync(
            timestamp: dateUtil.givenNow.addingTimeInterval(-100),
            location: LocationData(latitude: 0, longitude: 0)
        )

        let setup = makeCoordinator(storage: storage, dateUtil: dateUtil)
        // Same anchor → distance is 0; freshness gate skips API.
        let result = await setup.coordinator.refresh(latitude: 0, longitude: 0)

        #expect(result.isSuccess)
        #expect(setup.api.fetchAllGeofencesCallsCount == 0)
        #expect(setup.monitor.startedRegions.isEmpty)
    }

    @Test
    func refresh_givenFetchAllTimeFreshAndFarFromFetchAnchor_expectSkipNoApiCall() async {
        // Outrunning the fetch anchor does NOT force a re-fetch (the cached set is complete), and
        // with no ranking staleness it skips.
        let storage = makeStorage()
        let dateUtil = DateUtilStub()
        let oneHour: TimeInterval = 60 * 60
        await storage.setCachedConfig(GeofenceConfig(
            localRefreshTriggerRadius: 1000,
            remoteFetchRefreshTriggerRadius: 3000,
            remoteFetchRefreshExpiry: oneHour,
            duplicateEventsExpiry: 60,
            maxBusinessGeofences: 10,
            maxMonitoringDistance: GeofenceConstants.noMonitoringDistanceCap
        ))
        // Fetch anchor is far (~248km), but the registration anchor is at the refresh location, so
        // ranking is fresh — confirming fetchAll ignores fetch-anchor distance. Registered IDs
        // non-empty → not an unregistered-cache case.
        await storage.recordSync(timestamp: dateUtil.givenNow.addingTimeInterval(-100), location: LocationData(latitude: 0, longitude: 0))
        await storage.recordRegistration(center: LocationData(latitude: 1.0, longitude: 2.0), businessIds: ["a"])
        let setup = makeCoordinator(storage: storage, dateUtil: dateUtil, syncMode: .fetchAll)

        let result = await setup.coordinator.refresh(latitude: 1.0, longitude: 2.0)

        #expect(result.isSuccess)
        #expect(setup.api.fetchAllGeofencesCallsCount == 0)
        // Genuinely skipped (not a local re-rank): no regions registered this call.
        #expect(setup.monitor.startedRegions.isEmpty)
    }

    @Test
    func refresh_givenTimeFreshButRankingStale_expectLocalRerankNoApiCall() async {
        // Kill-then-travel: the app was dead so no movement EXIT fired, but the device is now beyond
        // the trigger radius from the last registration. Re-rank the cached set locally — no fetch.
        let storage = makeStorage()
        let dateUtil = DateUtilStub()
        let oneHour: TimeInterval = 60 * 60
        await storage.setCachedConfig(GeofenceConfig(
            localRefreshTriggerRadius: 1000,
            remoteFetchRefreshTriggerRadius: 3000,
            remoteFetchRefreshExpiry: oneHour,
            duplicateEventsExpiry: 60,
            maxBusinessGeofences: 10,
            maxMonitoringDistance: GeofenceConstants.noMonitoringDistanceCap
        ))
        await storage.recordSync(timestamp: dateUtil.givenNow.addingTimeInterval(-100), location: LocationData(latitude: 0, longitude: 0))
        await storage.recordRegistration(center: LocationData(latitude: 0, longitude: 0), businessIds: ["old"])
        await storage.setCachedGeofences([makeRegion(id: "near", latitude: 1, longitude: 2)])
        let setup = makeCoordinator(storage: storage, dateUtil: dateUtil, syncMode: .fetchAll)

        // ~248km from the registration center — well beyond the 1km ranking radius.
        let result = await setup.coordinator.refresh(latitude: 1.0, longitude: 2.0)

        #expect(result.isSuccess)
        #expect(setup.api.fetchAllGeofencesCallsCount == 0)
        #expect(setup.monitor.startedRegions.contains { $0.identifier == "near" })
    }

    @Test
    func refresh_givenTimeFreshAndRankingFreshButUnregisteredCache_expectLocalRerankNoApiCall() async {
        // Cache holds regions but nothing is registered — no registration center (regs lost on
        // sign-out / never restored) → re-register locally rather than skip, so the user isn't left
        // with no monitored geofences until staleness.
        let storage = makeStorage()
        let dateUtil = DateUtilStub()
        let oneHour: TimeInterval = 60 * 60
        await storage.setCachedConfig(GeofenceConfig(
            localRefreshTriggerRadius: 1000,
            remoteFetchRefreshTriggerRadius: 3000,
            remoteFetchRefreshExpiry: oneHour,
            duplicateEventsExpiry: 60,
            maxBusinessGeofences: 10,
            maxMonitoringDistance: GeofenceConstants.noMonitoringDistanceCap
        ))
        await storage.recordSync(timestamp: dateUtil.givenNow.addingTimeInterval(-100), location: LocationData(latitude: 0, longitude: 0))
        // No recordRegistration → no registration center → genuinely "nothing registered".
        await storage.setCachedGeofences([makeRegion(id: "cached", latitude: 0, longitude: 0)])
        let setup = makeCoordinator(storage: storage, dateUtil: dateUtil, syncMode: .fetchAll)

        // Same location as anchor → time-fresh + ranking-fresh, but nothing is registered.
        let result = await setup.coordinator.refresh(latitude: 0, longitude: 0)

        #expect(result.isSuccess)
        #expect(setup.api.fetchAllGeofencesCallsCount == 0)
        #expect(setup.monitor.startedRegions.contains { $0.identifier == "cached" })
    }

    @Test
    func refresh_givenTimeFreshRankingFreshAndFullyCappedOut_expectSkipNoRerank() async {
        // Every cached geofence is beyond maxMonitoringDistance, so the last registration registered
        // the movement trigger only (center set, zero business IDs). That's not "regs lost" — a
        // time/ranking-fresh refresh must skip, not re-rank on every launch.
        let storage = makeStorage()
        let dateUtil = DateUtilStub()
        let oneHour: TimeInterval = 60 * 60
        await storage.setCachedConfig(GeofenceConfig(
            localRefreshTriggerRadius: 1000,
            remoteFetchRefreshTriggerRadius: 3000,
            remoteFetchRefreshExpiry: oneHour,
            duplicateEventsExpiry: 60,
            maxBusinessGeofences: 10,
            maxMonitoringDistance: 5000
        ))
        await storage.recordSync(timestamp: dateUtil.givenNow.addingTimeInterval(-100), location: LocationData(latitude: 0, longitude: 0))
        // Prior capped-out registration: trigger registered (center set), no business IDs.
        await storage.recordRegistration(center: LocationData(latitude: 0, longitude: 0), businessIds: [])
        await storage.setCachedGeofences([makeRegion(id: "far", latitude: 1, longitude: 2)]) // ~248 km, beyond the 5 km cap
        let setup = makeCoordinator(storage: storage, dateUtil: dateUtil, syncMode: .fetchAll)

        let result = await setup.coordinator.refresh(latitude: 0, longitude: 0)

        #expect(result.isSuccess)
        #expect(setup.api.fetchAllGeofencesCallsCount == 0)
        // Genuinely skipped: no re-rank, so no stop/start churn this call.
        #expect(setup.monitor.startedRegions.isEmpty)
        #expect(setup.monitor.stopAllCallCount == 0)
    }

    @Test
    func refresh_givenTimeStaleButNearAnchor_expectApiCalled() async {
        let storage = makeStorage()
        let dateUtil = DateUtilStub()
        // Time-stale (2h ago vs 1h expiry) at the same anchor (distance = 0).
        let oneHour: TimeInterval = 60 * 60
        await storage.setCachedConfig(GeofenceConfig(
            localRefreshTriggerRadius: 1000,
            remoteFetchRefreshTriggerRadius: 3000,
            remoteFetchRefreshExpiry: oneHour,
            duplicateEventsExpiry: 60,
            maxBusinessGeofences: 10,
            maxMonitoringDistance: GeofenceConstants.noMonitoringDistanceCap
        ))
        await storage.recordSync(
            timestamp: dateUtil.givenNow.addingTimeInterval(-2 * oneHour),
            location: LocationData(latitude: 0, longitude: 0)
        )
        let api = GeofenceApiServiceMock()
        api.fetchAllGeofencesClosure = { completion in
            completion(.success(makeApiResponse(regions: [])))
        }
        let setup = makeCoordinator(api: api, storage: storage, dateUtil: dateUtil)

        let result = await setup.coordinator.refresh(latitude: 0, longitude: 0)

        #expect(result.isSuccess)
        #expect(api.fetchAllGeofencesCallsCount == 1)
    }

    @Test
    func refresh_givenStaleLastSync_expectApiCallAndPersist() async {
        let storage = makeStorage()
        let dateUtil = DateUtilStub()
        // Pin to integer-second precision so the roundtrip through `secondsSince1970`
        // encoding in GeofenceStorage doesn't lose sub-second bits in the comparison.
        dateUtil.givenNow = Date(timeIntervalSince1970: 1700000000)
        // Sync 25h ago → past the 24h fallback expiry.
        await storage.recordSync(
            timestamp: dateUtil.givenNow.addingTimeInterval(-25 * 60 * 60),
            location: LocationData(latitude: 0, longitude: 0)
        )
        let api = GeofenceApiServiceMock()
        let region = makeRegion(id: "g1", latitude: 1.0, longitude: 2.0)
        api.fetchAllGeofencesClosure = { completion in
            completion(.success(makeApiResponse(regions: [region])))
        }

        let setup = makeCoordinator(api: api, storage: storage, dateUtil: dateUtil)
        let result = await setup.coordinator.refresh(latitude: 1.0, longitude: 2.0)

        #expect(result.isSuccess)
        #expect(api.fetchAllGeofencesCallsCount == 1)
        let cached = await storage.getCachedGeofences()
        #expect(cached.map(\.id) == ["g1"])
        let lastSync = await storage.getLastSync()
        #expect(lastSync?.timestamp == dateUtil.givenNow)
        #expect(lastSync?.location.latitude == 1.0)
        #expect(lastSync?.location.longitude == 2.0)
    }

    @Test
    func refresh_givenNoCachedConfigAndSyncWithinFallback_expectSkip() async {
        let storage = makeStorage()
        let dateUtil = DateUtilStub()
        // 23h ago is under the 24h fallback expiry, so freshness gate skips the API call.
        await storage.recordSync(
            timestamp: dateUtil.givenNow.addingTimeInterval(-23 * 60 * 60),
            location: LocationData(latitude: 0, longitude: 0)
        )
        let setup = makeCoordinator(storage: storage, dateUtil: dateUtil)

        // Same anchor → distance is 0; freshness gate skips even without a cached config.
        let result = await setup.coordinator.refresh(latitude: 0, longitude: 0)

        #expect(result.isSuccess)
        #expect(setup.api.fetchAllGeofencesCallsCount == 0)
    }

    @Test
    func refresh_givenNoLastSync_expectApiCalled() async {
        // First-run path: no LastSyncRecord at all → freshness gate is bypassed and the
        // API is called regardless of cached-config state.
        let storage = makeStorage()
        let api = GeofenceApiServiceMock()
        api.fetchAllGeofencesClosure = { completion in
            completion(.success(makeApiResponse(regions: [])))
        }
        let setup = makeCoordinator(api: api, storage: storage)

        let result = await setup.coordinator.refresh(latitude: 1.0, longitude: 2.0)

        #expect(result.isSuccess)
        #expect(api.fetchAllGeofencesCallsCount == 1)
        #expect(await storage.getLastSync() != nil)
    }

    @Test
    func refresh_givenEmptyUserId_expectNoIdentifiedUser() async {
        let storage = makeStorage()
        let contextStore = makeContextStore(userId: nil)
        contextStore.setUserId("") // covers the `!userId.isEmpty` branch
        let setup = makeCoordinator(storage: storage, contextStore: contextStore)

        let result = await setup.coordinator.refresh(latitude: 1.0, longitude: 2.0)

        #expect(result.errorOrNil == .noIdentifiedUser)
        #expect(setup.api.fetchAllGeofencesCallsCount == 0)
    }

    // MARK: - Fetch outcomes

    @Test
    func refresh_givenApiTransportError_expectFailureAndNoCacheWritten() async {
        let storage = makeStorage()
        let api = GeofenceApiServiceMock()
        api.fetchAllGeofencesClosure = { completion in
            completion(.failure(.transport))
        }

        let setup = makeCoordinator(api: api, storage: storage)
        let result = await setup.coordinator.refresh(latitude: 1.0, longitude: 2.0)

        #expect(result.errorOrNil == .fetchFailed(.transport))
        let cached = await storage.getCachedGeofences()
        #expect(cached.isEmpty)
        let lastSync = await storage.getLastSync()
        #expect(lastSync == nil)
        #expect(setup.monitor.startedRegions.isEmpty)
    }

    @Test
    func refresh_givenResponseWithoutConfig_expectExistingCachedConfigPreserved() async {
        let storage = makeStorage()
        let priorConfig = GeofenceConfig(
            localRefreshTriggerRadius: 500,
            remoteFetchRefreshTriggerRadius: 1500,
            remoteFetchRefreshExpiry: 1800,
            duplicateEventsExpiry: 30,
            maxBusinessGeofences: 5,
            maxMonitoringDistance: GeofenceConstants.noMonitoringDistanceCap
        )
        await storage.setCachedConfig(priorConfig)
        let api = GeofenceApiServiceMock()
        api.fetchAllGeofencesClosure = { completion in
            completion(.success(makeApiResponse(regions: [])))
        }

        let setup = makeCoordinator(api: api, storage: storage)
        _ = await setup.coordinator.refresh(latitude: 1.0, longitude: 2.0)

        let cached = await storage.getCachedConfig()
        #expect(cached == priorConfig)
    }

    @Test
    func refresh_givenResponseWithConfig_expectCachedConfigUpdated() async {
        let storage = makeStorage()
        let newConfig = GeofenceConfig(
            localRefreshTriggerRadius: 750,
            remoteFetchRefreshTriggerRadius: 2500,
            remoteFetchRefreshExpiry: 7200,
            duplicateEventsExpiry: 90,
            maxBusinessGeofences: 8,
            maxMonitoringDistance: GeofenceConstants.noMonitoringDistanceCap
        )
        let api = GeofenceApiServiceMock()
        api.fetchAllGeofencesClosure = { completion in
            completion(.success(makeApiResponse(regions: [], config: newConfig)))
        }

        let setup = makeCoordinator(api: api, storage: storage)
        _ = await setup.coordinator.refresh(latitude: 1.0, longitude: 2.0)

        #expect(await storage.getCachedConfig() == newConfig)
    }

    // MARK: - OS registration

    @Test
    func refresh_givenMoreRegionsThanMax_expectNearestNRegisteredPlusMovementTrigger() async {
        let storage = makeStorage()
        let config = GeofenceConfig(
            localRefreshTriggerRadius: 1000,
            remoteFetchRefreshTriggerRadius: 3000,
            remoteFetchRefreshExpiry: 86400,
            duplicateEventsExpiry: 60,
            maxBusinessGeofences: 3,
            maxMonitoringDistance: GeofenceConstants.noMonitoringDistanceCap
        )
        await storage.setCachedConfig(config)

        // 5 regions; the 3 closest to origin (0,0) are g0/g1/g2.
        let regions = (0 ..< 5).map { i in
            makeRegion(id: "g\(i)", latitude: Double(i) * 0.1, longitude: 0)
        }
        let api = GeofenceApiServiceMock()
        api.fetchAllGeofencesClosure = { completion in
            completion(.success(makeApiResponse(regions: regions)))
        }

        let setup = makeCoordinator(api: api, storage: storage)
        _ = await setup.coordinator.refresh(latitude: 0, longitude: 0)

        let registeredIds = setup.monitor.startedRegions.map(\.identifier)
        #expect(registeredIds.contains("g0"))
        #expect(registeredIds.contains("g1"))
        #expect(registeredIds.contains("g2"))
        #expect(registeredIds.contains(GeofenceConstants.movementTriggerIdentifier))
        #expect(registeredIds.count == 4)
    }

    @Test
    func refresh_givenSuccess_expectMovementTriggerCenteredAtSyncLocationWithConfigRadius() async {
        let storage = makeStorage()
        let config = GeofenceConfig(
            localRefreshTriggerRadius: 750,
            remoteFetchRefreshTriggerRadius: 3000,
            remoteFetchRefreshExpiry: 86400,
            duplicateEventsExpiry: 60,
            maxBusinessGeofences: 10,
            maxMonitoringDistance: GeofenceConstants.noMonitoringDistanceCap
        )
        await storage.setCachedConfig(config)
        let api = GeofenceApiServiceMock()
        let region = makeRegion(id: "g1", latitude: 37.7749, longitude: -122.4194)
        api.fetchAllGeofencesClosure = { completion in
            completion(.success(makeApiResponse(regions: [region])))
        }

        let setup = makeCoordinator(api: api, storage: storage)
        _ = await setup.coordinator.refresh(latitude: 37.7749, longitude: -122.4194)

        let movementTrigger = setup.monitor.startedRegions.first {
            $0.identifier == GeofenceConstants.movementTriggerIdentifier
        }
        #expect(movementTrigger?.center.latitude == 37.7749)
        #expect(movementTrigger?.center.longitude == -122.4194)
        #expect(movementTrigger?.radius == 750)
        #expect(movementTrigger?.transitionTypes == [.exit])
    }

    @Test
    func refresh_givenEmptyBusinessRegions_expectNoMovementTriggerRegistered() async {
        let storage = makeStorage()
        let api = GeofenceApiServiceMock()
        api.fetchAllGeofencesClosure = { completion in
            completion(.success(makeApiResponse(regions: [])))
        }

        let setup = makeCoordinator(api: api, storage: storage)
        _ = await setup.coordinator.refresh(latitude: 37.7749, longitude: -122.4194)

        // No business regions ⇒ no movement trigger either; refetch-on-move would just hit the same empty result.
        #expect(setup.monitor.startedRegions.isEmpty)
    }

    @Test
    func refresh_givenSuccess_expectStopMonitoringAllBeforeStartMonitoring() async {
        let storage = makeStorage()
        let api = GeofenceApiServiceMock()
        let region = makeRegion(id: "g1", latitude: 1.0, longitude: 2.0)
        api.fetchAllGeofencesClosure = { completion in
            completion(.success(makeApiResponse(regions: [region])))
        }

        let setup = makeCoordinator(api: api, storage: storage)
        _ = await setup.coordinator.refresh(latitude: 1.0, longitude: 2.0)

        // Verify operations actually arrived in `stopAll → start business → start movement` order.
        #expect(setup.monitor.operationLog == [
            .stopAll,
            .start(identifier: "g1"),
            .start(identifier: GeofenceConstants.movementTriggerIdentifier)
        ])
    }

    // MARK: - Concurrency

    @Test
    func refresh_givenConcurrentCalls_expectSecondReturnsAlreadyInProgress() async {
        let storage = makeStorage()
        let api = GeofenceApiServiceMock()
        let firstReachedApi = AsyncSignal()
        let allowFinish = AsyncSignal()
        api.fetchAllGeofencesClosure = { completion in
            Task {
                await firstReachedApi.fire()
                await allowFinish.wait()
                completion(.success(GeofenceApiResponse(config: nil, geofences: [])))
            }
        }

        let setup = makeCoordinator(api: api, storage: storage)
        async let first = setup.coordinator.refresh(latitude: 1.0, longitude: 2.0)
        // Wait for the first call to enter the API mock before firing the second, so the
        // dedup-gate test is deterministic instead of timing-dependent.
        await firstReachedApi.wait()
        let second = await setup.coordinator.refresh(latitude: 3.0, longitude: 4.0)
        await allowFinish.fire()
        let firstResult = await first

        #expect(second.errorOrNil == .alreadyInProgress)
        #expect(firstResult.isSuccess)
        #expect(api.fetchAllGeofencesCallsCount == 1)
    }

    // MARK: - Storage invariants

    @Test
    func refresh_givenSuccess_expectStorageWritesInOrder_regionsThenConfigThenSync() async {
        // Order matters for tear-recovery: if `recordSync` lands before
        // `setCachedGeofences`, a process kill between the two leaves `lastSync` present
        // with a stale cache — the next refresh's freshness gate then skips the API and
        // the user silently has the wrong regions monitored.
        let backing = makeStorage()
        let spy = SpyGeofenceSyncStorage(underlying: backing)
        let api = GeofenceApiServiceMock()
        let newConfig = GeofenceConfig(
            localRefreshTriggerRadius: 750,
            remoteFetchRefreshTriggerRadius: 2500,
            remoteFetchRefreshExpiry: 7200,
            duplicateEventsExpiry: 90,
            maxBusinessGeofences: 8,
            maxMonitoringDistance: GeofenceConstants.noMonitoringDistanceCap
        )
        let region = makeRegion(id: "g1", latitude: 1.0, longitude: 2.0)
        api.fetchAllGeofencesClosure = { completion in
            completion(.success(makeApiResponse(regions: [region], config: newConfig)))
        }
        let setup = makeCoordinator(api: api, storage: spy)

        _ = await setup.coordinator.refresh(latitude: 1.0, longitude: 2.0)

        let writes = await spy.operations.filter { op in
            op == .setCachedGeofences || op == .setCachedConfig || op == .recordSync || op == .recordRegistration
        }
        #expect(writes == [.setCachedGeofences, .setCachedConfig, .recordSync, .recordRegistration])
    }

    @Test
    func refresh_givenRemoteFetch_expectRegistrationCenterAndIdsPersisted() async {
        // The remote path must persist the registration anchor + registered IDs — it's the
        // ranking-staleness reference a later cold-boot refresh measures against. Without it,
        // ranking staleness goes undetected after a kill-then-travel.
        let storage = makeStorage()
        let config = GeofenceConfig(
            localRefreshTriggerRadius: 1000,
            remoteFetchRefreshTriggerRadius: 3000,
            remoteFetchRefreshExpiry: 86400,
            duplicateEventsExpiry: 60,
            maxBusinessGeofences: 2,
            maxMonitoringDistance: GeofenceConstants.noMonitoringDistanceCap
        )
        // 3 regions; nearest 2 to the (0,0) fetch location are g0/g1.
        let regions = (0 ..< 3).map { i in makeRegion(id: "g\(i)", latitude: Double(i) * 0.1, longitude: 0) }
        let api = GeofenceApiServiceMock()
        api.fetchAllGeofencesClosure = { completion in
            completion(.success(makeApiResponse(regions: regions, config: config)))
        }
        let setup = makeCoordinator(api: api, storage: storage)

        _ = await setup.coordinator.refresh(latitude: 0, longitude: 0)

        #expect(await storage.getLastRegistrationCenter() == LocationData(latitude: 0, longitude: 0))
        #expect(await storage.getRegisteredBusinessIds() == ["g0", "g1"])
    }

    @Test
    func refresh_givenApiTransportError_expectCachedConfigUnchanged() async {
        let storage = makeStorage()
        let priorConfig = GeofenceConfig(
            localRefreshTriggerRadius: 500,
            remoteFetchRefreshTriggerRadius: 1500,
            remoteFetchRefreshExpiry: 1800,
            duplicateEventsExpiry: 30,
            maxBusinessGeofences: 5,
            maxMonitoringDistance: GeofenceConstants.noMonitoringDistanceCap
        )
        await storage.setCachedConfig(priorConfig)
        let api = GeofenceApiServiceMock()
        api.fetchAllGeofencesClosure = { completion in
            completion(.failure(.transport))
        }
        let setup = makeCoordinator(api: api, storage: storage)

        _ = await setup.coordinator.refresh(latitude: 1.0, longitude: 2.0)

        #expect(await storage.getCachedConfig() == priorConfig)
    }

    // MARK: - applyCachedRegistration

    private func sampleRegion(id: String = "g1", offset: Double = 0) -> Geofence {
        makeRegion(id: id, latitude: offset, longitude: 0)
    }

    @Test
    func applyCachedRegistration_givenNoUserId_expectNoRegistration() {
        let setup = makeCoordinator(storage: makeStorage())

        _ = setup.coordinator.applyCachedRegistration(
            cachedRegions: [sampleRegion()],
            anchor: LocationData(latitude: 0, longitude: 0),
            config: .fallback,
            userId: nil
        )

        #expect(setup.monitor.startedRegions.isEmpty)
    }

    @Test
    func applyCachedRegistration_givenEmptyRegions_expectNoRegistration() {
        let setup = makeCoordinator(storage: makeStorage())

        _ = setup.coordinator.applyCachedRegistration(
            cachedRegions: [],
            anchor: LocationData(latitude: 0, longitude: 0),
            config: .fallback,
            userId: "user-1"
        )

        #expect(setup.monitor.startedRegions.isEmpty)
    }

    @Test
    func applyCachedRegistration_givenMissingAnchor_expectNoRegistration() {
        // Without an anchor we can't distance-filter or place the movement trigger
        // sensibly — bail rather than re-using an arbitrary location.
        let setup = makeCoordinator(storage: makeStorage())

        _ = setup.coordinator.applyCachedRegistration(
            cachedRegions: [sampleRegion()],
            anchor: nil,
            config: .fallback,
            userId: "user-1"
        )

        #expect(setup.monitor.startedRegions.isEmpty)
    }

    @Test
    func applyCachedRegistration_givenAllInputs_expectNearestRegisteredPlusMovementTrigger() {
        let config = GeofenceConfig(
            localRefreshTriggerRadius: 600,
            remoteFetchRefreshTriggerRadius: 3000,
            remoteFetchRefreshExpiry: 86400,
            duplicateEventsExpiry: 60,
            maxBusinessGeofences: 3,
            maxMonitoringDistance: GeofenceConstants.noMonitoringDistanceCap
        )
        let anchor = LocationData(latitude: 37.7749, longitude: -122.4194)
        // 5 regions; nearest 3 to the anchor are g0/g1/g2.
        let regions = (0 ..< 5).map { i in
            makeRegion(id: "g\(i)", latitude: anchor.latitude + Double(i) * 0.01, longitude: anchor.longitude)
        }
        let setup = makeCoordinator(storage: makeStorage())

        _ = setup.coordinator.applyCachedRegistration(
            cachedRegions: regions,
            anchor: anchor,
            config: config,
            userId: "user-1"
        )

        let registeredIds = setup.monitor.startedRegions.map(\.identifier)
        #expect(registeredIds.contains("g0"))
        #expect(registeredIds.contains("g1"))
        #expect(registeredIds.contains("g2"))
        #expect(registeredIds.contains(GeofenceConstants.movementTriggerIdentifier))
        #expect(registeredIds.count == 4)

        let trigger = setup.monitor.startedRegions.first {
            $0.identifier == GeofenceConstants.movementTriggerIdentifier
        }
        #expect(trigger?.center.latitude == anchor.latitude)
        #expect(trigger?.center.longitude == anchor.longitude)
        #expect(trigger?.radius == 600)
        #expect(trigger?.transitionTypes == [.exit])
    }

    @Test
    func applyCachedRegistration_givenAllInputs_expectReturnsRegisteredCenterAndIds() {
        // The caller persists this as the ranking-staleness reference, so the returned center/ids
        // must match what was registered with the OS (the nearest set, capped at maxBusinessGeofences).
        let config = GeofenceConfig(
            localRefreshTriggerRadius: 600,
            remoteFetchRefreshTriggerRadius: 3000,
            remoteFetchRefreshExpiry: 86400,
            duplicateEventsExpiry: 60,
            maxBusinessGeofences: 3,
            maxMonitoringDistance: GeofenceConstants.noMonitoringDistanceCap
        )
        let anchor = LocationData(latitude: 37.7749, longitude: -122.4194)
        let regions = (0 ..< 5).map { i in
            makeRegion(id: "g\(i)", latitude: anchor.latitude + Double(i) * 0.01, longitude: anchor.longitude)
        }
        let setup = makeCoordinator(storage: makeStorage())

        let registration = setup.coordinator.applyCachedRegistration(
            cachedRegions: regions,
            anchor: anchor,
            config: config,
            userId: "user-1"
        )

        #expect(registration?.center == anchor)
        #expect(registration?.businessIds == ["g0", "g1", "g2"])
    }

    @Test
    func applyCachedRegistration_givenSkipped_expectNilReturn() {
        let setup = makeCoordinator(storage: makeStorage())

        let registration = setup.coordinator.applyCachedRegistration(
            cachedRegions: [sampleRegion()],
            anchor: LocationData(latitude: 0, longitude: 0),
            config: .fallback,
            userId: nil
        )

        #expect(registration == nil)
    }

    @Test
    func applyCachedRegistration_givenAllRegionsBeyondCap_expectMovementTriggerButNoBusinessRegions() {
        // The distance cap excludes the only cached region; the movement trigger must still register
        // so a later EXIT re-ranks and can bring a now-closer region into range.
        let config = GeofenceConfig(
            localRefreshTriggerRadius: 600,
            remoteFetchRefreshTriggerRadius: 3000,
            remoteFetchRefreshExpiry: 86400,
            duplicateEventsExpiry: 60,
            maxBusinessGeofences: 10,
            maxMonitoringDistance: 5000
        )
        let setup = makeCoordinator(storage: makeStorage())

        let registration = setup.coordinator.applyCachedRegistration(
            cachedRegions: [makeRegion(id: "far", latitude: 1, longitude: 2)], // ~248 km from anchor
            anchor: LocationData(latitude: 0, longitude: 0),
            config: config,
            userId: "user-1"
        )

        #expect(setup.monitor.startedRegions.map(\.identifier) == [GeofenceConstants.movementTriggerIdentifier])
        #expect(registration?.businessIds.isEmpty == true)
    }

    @Test
    func applyCachedRegistration_givenKillSwitch_expectNoRegistrationIncludingTrigger() {
        // maxBusinessGeofences == 0 disables registration entirely — not even the movement trigger.
        let config = GeofenceConfig(
            localRefreshTriggerRadius: 600,
            remoteFetchRefreshTriggerRadius: 3000,
            remoteFetchRefreshExpiry: 86400,
            duplicateEventsExpiry: 60,
            maxBusinessGeofences: 0,
            maxMonitoringDistance: GeofenceConstants.noMonitoringDistanceCap
        )
        let setup = makeCoordinator(storage: makeStorage())

        _ = setup.coordinator.applyCachedRegistration(
            cachedRegions: [makeRegion(id: "g1", latitude: 0, longitude: 0)],
            anchor: LocationData(latitude: 0, longitude: 0),
            config: config,
            userId: "user-1"
        )

        #expect(setup.monitor.startedRegions.isEmpty)
    }

    @Test
    func applyCachedRegistration_givenNilConfig_expectFallbackUsed() {
        let anchor = LocationData(latitude: 0, longitude: 0)
        let setup = makeCoordinator(storage: makeStorage())

        _ = setup.coordinator.applyCachedRegistration(
            cachedRegions: [sampleRegion(offset: 0.1)],
            anchor: anchor,
            config: nil,
            userId: "user-1"
        )

        let trigger = setup.monitor.startedRegions.first {
            $0.identifier == GeofenceConstants.movementTriggerIdentifier
        }
        #expect(trigger?.radius == GeofenceConstants.movementTriggerRadius)
    }

    @Test
    func applyCachedRegistration_givenInFlightRefresh_expectSkipped() async {
        let storage = makeStorage()
        let api = GeofenceApiServiceMock()
        let firstReachedApi = AsyncSignal()
        let allowFinish = AsyncSignal()
        api.fetchAllGeofencesClosure = { completion in
            Task {
                await firstReachedApi.fire()
                await allowFinish.wait()
                completion(.success(GeofenceApiResponse(config: nil, geofences: [])))
            }
        }
        let setup = makeCoordinator(api: api, storage: storage)
        async let refreshResult = setup.coordinator.refresh(latitude: 1.0, longitude: 2.0)
        await firstReachedApi.wait()

        // Refresh holds the dedup gate. ApplyCachedRegistration must bail without touching
        // the monitor.
        let monitorCallsBefore = setup.monitor.startedRegions.count
        _ = setup.coordinator.applyCachedRegistration(
            cachedRegions: [sampleRegion()],
            anchor: LocationData(latitude: 0, longitude: 0),
            config: .fallback,
            userId: "user-1"
        )
        #expect(setup.monitor.startedRegions.count == monitorCallsBefore)

        await allowFinish.fire()
        _ = await refreshResult
    }

    @Test
    func refresh_afterEarlyReturn_expectGateReleasedAndSecondRefreshSucceeds() async {
        // Confirms `defer { refreshInProgress = false }` actually runs on the
        // `noIdentifiedUser` early-return path. A leaked gate would silently lock the
        // coordinator out of every future refresh — silent because the second call would
        // return `.alreadyInProgress`, not an obvious crash.
        let storage = makeStorage()
        let contextStore = makeContextStore(userId: nil)
        let api = GeofenceApiServiceMock()
        api.fetchAllGeofencesClosure = { completion in
            completion(.success(makeApiResponse(regions: [])))
        }
        let setup = makeCoordinator(api: api, storage: storage, contextStore: contextStore)

        let first = await setup.coordinator.refresh(latitude: 1.0, longitude: 2.0)
        #expect(first.errorOrNil == .noIdentifiedUser)

        // User signs in between calls.
        contextStore.setUserId("user-1")
        let second = await setup.coordinator.refresh(latitude: 1.0, longitude: 2.0)

        #expect(second.isSuccess)
        #expect(api.fetchAllGeofencesCallsCount == 1)
    }

    // MARK: - handleMovement

    @Test
    func handleMovement_givenNoUserId_expectFailureAndNoApiCall() async {
        let storage = makeStorage()
        let setup = makeCoordinator(storage: storage, contextStore: makeContextStore(userId: nil))

        let result = await setup.coordinator.handleMovement(latitude: 1.0, longitude: 2.0)

        #expect(result.errorOrNil == .noIdentifiedUser)
        #expect(setup.api.fetchAllGeofencesCallsCount == 0)
        #expect(setup.monitor.startedRegions.isEmpty)
    }

    @Test
    func handleMovement_givenNoAnchor_expectTierBRemoteFetch() async {
        // No prior sync → no anchor → can't distance-compare, so default to remote fetch.
        // Matches Android's `anchor == null` branch.
        let storage = makeStorage()
        let api = GeofenceApiServiceMock()
        api.fetchAllGeofencesClosure = { completion in
            completion(.success(makeApiResponse(regions: [makeRegion(id: "g1", latitude: 0, longitude: 0)])))
        }
        let setup = makeCoordinator(api: api, storage: storage)

        let result = await setup.coordinator.handleMovement(latitude: 1.0, longitude: 2.0)

        #expect(result.isSuccess)
        #expect(setup.api.fetchAllGeofencesCallsCount == 1)
    }

    @Test
    func handleMovement_givenMovementWithinThreshold_expectTierALocalRerankAndNoApiCall() async {
        let storage = makeStorage()
        let config = GeofenceConfig(
            localRefreshTriggerRadius: 1000,
            remoteFetchRefreshTriggerRadius: 5000,
            remoteFetchRefreshExpiry: 3600,
            duplicateEventsExpiry: 3600,
            maxBusinessGeofences: 10,
            maxMonitoringDistance: GeofenceConstants.noMonitoringDistanceCap
        )
        await storage.setCachedConfig(config)
        // Anchor at (0, 0); cached regions arrayed nearby for re-rank verification.
        await storage.recordSync(timestamp: Date(timeIntervalSince1970: 100), location: LocationData(latitude: 0, longitude: 0))
        await storage.setCachedGeofences([
            makeRegion(id: "near", latitude: 0, longitude: 0.0005),
            makeRegion(id: "far", latitude: 1, longitude: 1)
        ])
        let api = GeofenceApiServiceMock()
        let setup = makeCoordinator(api: api, storage: storage)

        // New position ~111 m from anchor — re-ranks the cached set locally, no fetch.
        let result = await setup.coordinator.handleMovement(latitude: 0, longitude: 0.001)

        #expect(result.isSuccess)
        #expect(setup.api.fetchAllGeofencesCallsCount == 0)
        let businessRegistered = setup.monitor.startedRegions.filter { $0.identifier != GeofenceConstants.movementTriggerIdentifier }
        #expect(businessRegistered.map(\.identifier) == ["near", "far"])
    }

    @Test
    func handleMovement_givenFetchAllMovementBeyondThreshold_expectLocalRerankNoApiCall() async {
        // fetchAll holds the complete set, so even a large move never re-fetches — it re-ranks the
        // cached regions on-device. No code path sends location off-device.
        let storage = makeStorage()
        let config = GeofenceConfig(
            localRefreshTriggerRadius: 1000,
            remoteFetchRefreshTriggerRadius: 5000,
            remoteFetchRefreshExpiry: 3600,
            duplicateEventsExpiry: 3600,
            maxBusinessGeofences: 10,
            maxMonitoringDistance: GeofenceConstants.noMonitoringDistanceCap
        )
        await storage.setCachedConfig(config)
        await storage.recordSync(timestamp: Date(timeIntervalSince1970: 100), location: LocationData(latitude: 0, longitude: 0))
        await storage.setCachedGeofences([makeRegion(id: "cached", latitude: 1, longitude: 1)])
        let setup = makeCoordinator(storage: storage, syncMode: .fetchAll)

        // ~157 km from anchor — a large move that still re-ranks locally, never re-fetches.
        let result = await setup.coordinator.handleMovement(latitude: 1.0, longitude: 1.0)

        #expect(result.isSuccess)
        #expect(setup.api.fetchAllGeofencesCallsCount == 0)
        #expect(setup.monitor.startedRegions.contains { $0.identifier == "cached" })
    }

    @Test
    func handleMovement_givenLocalRerank_expectLastSyncAndCacheNotMutated() async {
        // A local re-rank re-uses the existing API anchor — must not overwrite lastSync, or the
        // time-staleness reference would drift to wherever the user just stood.
        let storage = makeStorage()
        let originalAnchor = LocationData(latitude: 0, longitude: 0)
        let originalTimestamp = Date(timeIntervalSince1970: 100)
        let config = GeofenceConfig(
            localRefreshTriggerRadius: 1000,
            remoteFetchRefreshTriggerRadius: 5000,
            remoteFetchRefreshExpiry: 3600,
            duplicateEventsExpiry: 3600,
            maxBusinessGeofences: 10,
            maxMonitoringDistance: GeofenceConstants.noMonitoringDistanceCap
        )
        await storage.setCachedConfig(config)
        await storage.recordSync(timestamp: originalTimestamp, location: originalAnchor)
        await storage.setCachedGeofences([makeRegion(id: "g1", latitude: 0, longitude: 0)])
        let setup = makeCoordinator(storage: storage)

        _ = await setup.coordinator.handleMovement(latitude: 0, longitude: 0.001)

        let lastSync = await storage.getLastSync()
        #expect(lastSync?.location == originalAnchor)
        #expect(lastSync?.timestamp == originalTimestamp)
    }

    @Test
    func handleMovement_givenLocalRerank_expectRegistrationCenterAndIdsPersistedAtNewLocation() async {
        // A local re-rank must advance the registration reference to the new location, so the next
        // refresh's ranking-staleness check measures from where the device actually re-registered.
        let storage = makeStorage()
        let config = GeofenceConfig(
            localRefreshTriggerRadius: 1000,
            remoteFetchRefreshTriggerRadius: 5000,
            remoteFetchRefreshExpiry: 3600,
            duplicateEventsExpiry: 3600,
            maxBusinessGeofences: 10,
            maxMonitoringDistance: GeofenceConstants.noMonitoringDistanceCap
        )
        await storage.setCachedConfig(config)
        await storage.recordSync(timestamp: Date(timeIntervalSince1970: 100), location: LocationData(latitude: 0, longitude: 0))
        await storage.setCachedGeofences([makeRegion(id: "near", latitude: 0, longitude: 0.0005)])
        let setup = makeCoordinator(storage: storage)

        let newLocation = LocationData(latitude: 0, longitude: 0.001)
        _ = await setup.coordinator.handleMovement(latitude: newLocation.latitude, longitude: newLocation.longitude)

        #expect(await storage.getLastRegistrationCenter() == newLocation)
        #expect(await storage.getRegisteredBusinessIds() == ["near"])
    }

    @Test
    func handleMovement_givenLocalRerank_expectMovementTriggerRecenteredAtNewLocation() async {
        // The movement trigger's job is to fire when the user leaves the *current* zone.
        // After a local re-rank, it must center on where the user just stood, not the API anchor.
        let storage = makeStorage()
        let config = GeofenceConfig(
            localRefreshTriggerRadius: 1000,
            remoteFetchRefreshTriggerRadius: 5000,
            remoteFetchRefreshExpiry: 3600,
            duplicateEventsExpiry: 3600,
            maxBusinessGeofences: 10,
            maxMonitoringDistance: GeofenceConstants.noMonitoringDistanceCap
        )
        await storage.setCachedConfig(config)
        await storage.recordSync(timestamp: Date(timeIntervalSince1970: 100), location: LocationData(latitude: 0, longitude: 0))
        await storage.setCachedGeofences([makeRegion(id: "near", latitude: 0, longitude: 0.0005)])
        let setup = makeCoordinator(storage: storage)

        let newLocation = LocationData(latitude: 0, longitude: 0.001)
        _ = await setup.coordinator.handleMovement(latitude: newLocation.latitude, longitude: newLocation.longitude)

        let movementTrigger = setup.monitor.startedRegions.first { $0.identifier == GeofenceConstants.movementTriggerIdentifier }
        #expect(movementTrigger?.center == newLocation)
        #expect(movementTrigger?.radius == config.localRefreshTriggerRadius)
    }

    @Test
    func handleMovement_givenInFlightRefresh_expectAlreadyInProgress() async {
        // Shared `refreshInProgress` gate — a refresh holding it must short-circuit
        // a concurrent movement EXIT. Verified by suspending the API mid-fetch on the
        // first call, then issuing handleMovement while it's pending.
        let storage = makeStorage()
        let api = GeofenceApiServiceMock()
        let suspendUntil = AsyncSignal()
        let arrived = AsyncSignal()
        api.fetchAllGeofencesClosure = { completion in
            Task {
                await arrived.fire()
                await suspendUntil.wait()
                completion(.success(makeApiResponse(regions: [])))
            }
        }
        let setup = makeCoordinator(api: api, storage: storage)

        async let firstRefresh = setup.coordinator.refresh(latitude: 0, longitude: 0)
        await arrived.wait()
        let movement = await setup.coordinator.handleMovement(latitude: 0, longitude: 0)
        await suspendUntil.fire()
        _ = await firstRefresh

        #expect(movement.errorOrNil == .alreadyInProgress)
    }

    // MARK: - reset

    @Test
    func reset_givenNoSignedInUser_expectStopMonitoringAndClearUserScopedState() async {
        let storage = makeStorage()
        await storage.setCachedGeofences([makeRegion(id: "keep", latitude: 0, longitude: 0)])
        await storage.setCachedConfig(.fallback)
        await storage.recordSync(timestamp: Date(timeIntervalSince1970: 100), location: LocationData(latitude: 0, longitude: 0))
        _ = await storage.tryAcquireCooldown(key: "user-scoped", now: Date(timeIntervalSince1970: 100), interval: 3600)
        let setup = makeCoordinator(storage: storage, contextStore: makeContextStore(userId: nil))

        let result = await setup.coordinator.reset()

        #expect(result.isSuccess)
        #expect(setup.monitor.stopAllCallCount == 1)
        // Workspace cache survives; user-scoped state is wiped.
        let remainingRegions = await storage.getCachedGeofences()
        let remainingConfig = await storage.getCachedConfig()
        let remainingLastSync = await storage.getLastSync()
        let remainingCooldowns = await storage.getEventCooldowns()
        #expect(remainingRegions.map(\.id) == ["keep"])
        #expect(remainingConfig != nil)
        #expect(remainingLastSync == nil)
        #expect(remainingCooldowns.isEmpty)
    }

    @Test
    func reset_givenAnotherUserSignedIn_expectSkippedWithoutChanges() async {
        // A re-login during the reset window must NOT wipe the new user's freshly-set state.
        let storage = makeStorage()
        await storage.setCachedGeofences([makeRegion(id: "keep", latitude: 0, longitude: 0)])
        await storage.recordSync(timestamp: Date(timeIntervalSince1970: 100), location: LocationData(latitude: 0, longitude: 0))
        _ = await storage.tryAcquireCooldown(key: "g1:enter", now: Date(timeIntervalSince1970: 100), interval: 3600)
        let setup = makeCoordinator(storage: storage, contextStore: makeContextStore(userId: "new-user"))

        let result = await setup.coordinator.reset()

        #expect(result.isSuccess)
        #expect(setup.monitor.stopAllCallCount == 0)
        let lastSync = await storage.getLastSync()
        let cooldowns = await storage.getEventCooldowns()
        #expect(lastSync != nil)
        #expect(cooldowns.count == 1)
    }

    @Test
    func reset_givenInFlightRefresh_expectAlreadyInProgress() async {
        let storage = makeStorage()
        let api = GeofenceApiServiceMock()
        let suspendUntil = AsyncSignal()
        let arrived = AsyncSignal()
        api.fetchAllGeofencesClosure = { completion in
            Task {
                await arrived.fire()
                await suspendUntil.wait()
                completion(.success(makeApiResponse(regions: [])))
            }
        }
        let setup = makeCoordinator(api: api, storage: storage)

        async let firstRefresh = setup.coordinator.refresh(latitude: 0, longitude: 0)
        await arrived.wait()
        let resetResult = await setup.coordinator.reset()
        await suspendUntil.fire()
        _ = await firstRefresh

        #expect(resetResult.errorOrNil == .alreadyInProgress)
    }

    // MARK: - userId recheck after API

    @Test
    func refresh_givenUserSignedOutMidFetch_expectNoStorageWritesAndNoRegister() async {
        let storage = makeStorage()
        let contextStore = makeContextStore(userId: "user-1")
        let api = GeofenceApiServiceMock()
        let suspendUntil = AsyncSignal()
        let arrived = AsyncSignal()
        api.fetchAllGeofencesClosure = { completion in
            Task {
                await arrived.fire()
                await suspendUntil.wait()
                completion(.success(makeApiResponse(regions: [makeRegion(id: "g1", latitude: 0, longitude: 0)])))
            }
        }
        let setup = makeCoordinator(api: api, storage: storage, contextStore: contextStore)

        async let refreshResult = setup.coordinator.refresh(latitude: 0, longitude: 0)
        await arrived.wait()
        // User signs out while the API call is pending.
        contextStore.setUserId(nil)
        await suspendUntil.fire()
        let result = await refreshResult

        #expect(result.isSuccess)
        // No register, no persistence — the result was attributed to a stale user.
        #expect(setup.monitor.startedRegions.isEmpty)
        let cached = await storage.getCachedGeofences()
        #expect(cached.isEmpty)
        let lastSync = await storage.getLastSync()
        #expect(lastSync == nil)
    }

    @Test
    func refresh_givenDifferentUserSignsInMidFetch_expectNoStorageWritesAndNoRegister() async {
        let storage = makeStorage()
        let contextStore = makeContextStore(userId: "user-1")
        let api = GeofenceApiServiceMock()
        let suspendUntil = AsyncSignal()
        let arrived = AsyncSignal()
        api.fetchAllGeofencesClosure = { completion in
            Task {
                await arrived.fire()
                await suspendUntil.wait()
                completion(.success(makeApiResponse(regions: [makeRegion(id: "g1", latitude: 0, longitude: 0)])))
            }
        }
        let setup = makeCoordinator(api: api, storage: storage, contextStore: contextStore)

        async let refreshResult = setup.coordinator.refresh(latitude: 0, longitude: 0)
        await arrived.wait()
        contextStore.setUserId("user-2")
        await suspendUntil.fire()
        let result = await refreshResult

        #expect(result.isSuccess)
        #expect(setup.monitor.startedRegions.isEmpty)
        let cached = await storage.getCachedGeofences()
        #expect(cached.isEmpty)
    }

    @Test
    func refresh_givenInFlightHandleMovement_expectAlreadyInProgress() async {
        // Reverse direction of the cross-entry gate — handleMovement holding it must
        // short-circuit a concurrent refresh. Pinned independently because a regression
        // that gave handleMovement its own gate would still pass the forward test.
        let storage = makeStorage()
        // No cached config → handleMovement falls back to `.fallback`; no anchor → remote bootstrap.
        let api = GeofenceApiServiceMock()
        let suspendUntil = AsyncSignal()
        let arrived = AsyncSignal()
        api.fetchAllGeofencesClosure = { completion in
            Task {
                await arrived.fire()
                await suspendUntil.wait()
                completion(.success(makeApiResponse(regions: [])))
            }
        }
        let setup = makeCoordinator(api: api, storage: storage)

        async let firstMovement = setup.coordinator.handleMovement(latitude: 0, longitude: 0)
        await arrived.wait()
        let refreshResult = await setup.coordinator.refresh(latitude: 0, longitude: 0)
        await suspendUntil.fire()
        _ = await firstMovement

        #expect(refreshResult.errorOrNil == .alreadyInProgress)
    }
}

// MARK: - Result matchers

private extension Result where Success == Void {
    var isSuccess: Bool {
        if case .success = self { return true } else { return false }
    }

    var errorOrNil: Failure? {
        if case .failure(let error) = self { return error } else { return nil }
    }
}

// MARK: - Storage spy

/// Records calls in arrival order; delegates to a real `GeofenceStorage` so state
/// correctness still flows through the production code.
private actor SpyGeofenceSyncStorage: GeofenceSyncStorage {
    enum Operation: Sendable, Equatable {
        case getCachedConfig
        case getCachedGeofences
        case getLastSync
        case getLastRegistrationCenter
        case getRegisteredBusinessIds
        case setCachedGeofences
        case setCachedConfig
        case recordSync
        case recordRegistration
        case clearUserScopedState
    }

    private let underlying: GeofenceStorage
    private(set) var operations: [Operation] = []

    init(underlying: GeofenceStorage) {
        self.underlying = underlying
    }

    func getCachedConfig() async -> GeofenceConfig? {
        operations.append(.getCachedConfig)
        return await underlying.getCachedConfig()
    }

    func getCachedGeofences() async -> [Geofence] {
        operations.append(.getCachedGeofences)
        return await underlying.getCachedGeofences()
    }

    func getLastSync() async -> LastSyncRecord? {
        operations.append(.getLastSync)
        return await underlying.getLastSync()
    }

    func getLastRegistrationCenter() async -> LocationData? {
        operations.append(.getLastRegistrationCenter)
        return await underlying.getLastRegistrationCenter()
    }

    func getRegisteredBusinessIds() async -> Set<String> {
        operations.append(.getRegisteredBusinessIds)
        return await underlying.getRegisteredBusinessIds()
    }

    func setCachedGeofences(_ regions: [Geofence]) async {
        operations.append(.setCachedGeofences)
        await underlying.setCachedGeofences(regions)
    }

    func setCachedConfig(_ config: GeofenceConfig) async {
        operations.append(.setCachedConfig)
        await underlying.setCachedConfig(config)
    }

    func recordSync(timestamp: Date, location: LocationData) async {
        operations.append(.recordSync)
        await underlying.recordSync(timestamp: timestamp, location: location)
    }

    func recordRegistration(center: LocationData, businessIds: Set<String>) async {
        operations.append(.recordRegistration)
        await underlying.recordRegistration(center: center, businessIds: businessIds)
    }

    func clearUserScopedState() async {
        operations.append(.clearUserScopedState)
        await underlying.clearUserScopedState()
    }
}

// MARK: - Async signal helper

/// One Task awaits `wait()` until another Task calls `fire()`.
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
