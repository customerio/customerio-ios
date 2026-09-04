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
        let emitter: TransitionEmitterSpy
    }

    private func makeCoordinator(
        api: GeofenceApiServiceMock = GeofenceApiServiceMock(),
        storage: GeofenceSyncStorage,
        monitor: MockGeofenceRegionMonitor? = nil,
        contextStore: BackgroundDeliveryContextStore? = nil,
        emitter: TransitionEmitterSpy = TransitionEmitterSpy(),
        dateUtil: DateUtilStub = DateUtilStub()
    ) -> Setup {
        let resolvedContextStore = contextStore ?? makeContextStore()
        let resolvedMonitor = monitor ?? MockGeofenceRegionMonitor()
        let coordinator = GeofenceSyncCoordinatorImpl(
            apiService: api,
            storage: storage,
            monitor: resolvedMonitor,
            contextStore: resolvedContextStore,
            transitionEmitter: emitter,
            dateUtil: dateUtil,
            logger: LoggerMock()
        )
        return Setup(
            coordinator: coordinator,
            api: api,
            monitor: resolvedMonitor,
            contextStore: resolvedContextStore,
            dateUtil: dateUtil,
            emitter: emitter
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
                shape: region.vertices == nil ? "circle" : "polygon",
                latitude: region.vertices == nil ? region.latitude : nil,
                longitude: region.vertices == nil ? region.longitude : nil,
                radius: region.vertices == nil ? region.radius : nil,
                geometry: region.vertices.map { ring in
                    GeofenceApiGeometry(
                        type: "Polygon",
                        coordinates: [ring.map { [$0.longitude, $0.latitude] }]
                    )
                },
                enclosingCircle: region.vertices == nil ? nil : GeofenceApiEnclosingCircle(
                    latitude: region.latitude,
                    longitude: region.longitude,
                    baseRadiusM: region.radius
                ),
                externalId: nil,
                transitionTypes: region.transitionTypes.map(\.rawValue),
                lastUpdated: region.lastUpdated.timeIntervalSince1970,
                geosetIds: region.geosetIds.isEmpty ? nil : region.geosetIds,
                metadata: region.metadata.isEmpty ? nil : region.metadata
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
                ios: GeofenceApiPlatformConfig(maxBusinessGeofence: config.maxBusinessGeofences)
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
        #expect(setup.api.fetchNearbyGeofencesCallsCount == 0)
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
        #expect(setup.api.fetchNearbyGeofencesCallsCount == 0)
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
        let setup = makeCoordinator(storage: storage, dateUtil: dateUtil)

        // ~2.2km from the anchor: beyond the 1km trigger radius (ranking stale) but within the 3km
        // refetch radius (no remote fetch).
        let result = await setup.coordinator.refresh(latitude: 0.02, longitude: 0)

        #expect(result.isSuccess)
        #expect(setup.api.fetchNearbyGeofencesCallsCount == 0)
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
        let setup = makeCoordinator(storage: storage, dateUtil: dateUtil)

        // Same location as anchor → time-fresh + ranking-fresh, but nothing is registered.
        let result = await setup.coordinator.refresh(latitude: 0, longitude: 0)

        #expect(result.isSuccess)
        #expect(setup.api.fetchNearbyGeofencesCallsCount == 0)
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
        let setup = makeCoordinator(storage: storage, dateUtil: dateUtil)

        let result = await setup.coordinator.refresh(latitude: 0, longitude: 0)

        #expect(result.isSuccess)
        #expect(setup.api.fetchNearbyGeofencesCallsCount == 0)
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
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            completion(.success(makeApiResponse(regions: [])))
        }
        let setup = makeCoordinator(api: api, storage: storage, dateUtil: dateUtil)

        let result = await setup.coordinator.refresh(latitude: 0, longitude: 0)

        #expect(result.isSuccess)
        #expect(api.fetchNearbyGeofencesCallsCount == 1)
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
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            completion(.success(makeApiResponse(regions: [region])))
        }

        let setup = makeCoordinator(api: api, storage: storage, dateUtil: dateUtil)
        let result = await setup.coordinator.refresh(latitude: 1.0, longitude: 2.0)

        #expect(result.isSuccess)
        #expect(api.fetchNearbyGeofencesCallsCount == 1)
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
        #expect(setup.api.fetchNearbyGeofencesCallsCount == 0)
    }

    @Test
    func refresh_givenNoLastSync_expectApiCalled() async {
        // First-run path: no LastSyncRecord at all → freshness gate is bypassed and the
        // API is called regardless of cached-config state.
        let storage = makeStorage()
        let api = GeofenceApiServiceMock()
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            completion(.success(makeApiResponse(regions: [])))
        }
        let setup = makeCoordinator(api: api, storage: storage)

        let result = await setup.coordinator.refresh(latitude: 1.0, longitude: 2.0)

        #expect(result.isSuccess)
        #expect(api.fetchNearbyGeofencesCallsCount == 1)
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
        #expect(setup.api.fetchNearbyGeofencesCallsCount == 0)
    }

    // MARK: - Fetch outcomes

    @Test
    func refresh_givenApiTransportError_expectFailureAndNoCacheWritten() async {
        let storage = makeStorage()
        let api = GeofenceApiServiceMock()
        api.fetchNearbyGeofencesClosure = { _, _, completion in
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
        api.fetchNearbyGeofencesClosure = { _, _, completion in
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
        api.fetchNearbyGeofencesClosure = { _, _, completion in
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
        api.fetchNearbyGeofencesClosure = { _, _, completion in
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
        api.fetchNearbyGeofencesClosure = { _, _, completion in
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

    /// A payload whose regions all fail to resolve is a broken response, not a geofence-free area:
    /// treating it as the latter would wipe the cache and deregister every fence the user has.
    @Test
    func refresh_givenEveryRegionUnusable_expectFetchFailureAndCacheKept() async {
        let storage = makeStorage()
        await storage.setCachedGeofences([makeRegion(id: "kept", latitude: 37.7749, longitude: -122.4194)])
        let unusable = GeofenceApiRegion(
            id: "broken", name: nil, shape: "circle",
            latitude: 91, longitude: 2, radius: 100,
            geometry: nil, enclosingCircle: nil, externalId: nil,
            transitionTypes: nil, lastUpdated: nil, geosetIds: nil, metadata: nil
        )
        let api = GeofenceApiServiceMock()
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            completion(.success(GeofenceApiResponse(config: nil, geofences: [unusable])))
        }

        let setup = makeCoordinator(api: api, storage: storage)
        let result = await setup.coordinator.refresh(latitude: 37.7749, longitude: -122.4194)

        #expect(result.errorOrNil == .fetchFailed(.decoding))
        let cached = await storage.getCachedGeofences()
        #expect(cached.map(\.id) == ["kept"])
        #expect(setup.monitor.startedRegions.isEmpty)
    }

    /// The loss that never reaches `toDomainRegions`: a region rejected at JSON decode is compacted
    /// out of `geofences` before the domain mapping runs, so no drop callback fires for it. It is
    /// still an unreadable payload, and treating it as "no geofences" wipes the cache.
    ///
    /// Built through `JSONDecoder` deliberately — the memberwise init sets `receivedRegionCount`
    /// from the surviving array, so it cannot express "one arrived, none survived".
    @Test
    func refresh_givenEveryRegionLostAtJsonDecode_expectFetchFailureAndCacheKept() async throws {
        let storage = makeStorage()
        await storage.setCachedGeofences([makeRegion(id: "kept", latitude: 37.7749, longitude: -122.4194)])
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload = #"{"geofences":[{"id":{},"latitude":1,"longitude":2,"radius":100}]}"#
        let response = try decoder.decode(GeofenceApiResponse.self, from: Data(payload.utf8))
        #expect(response.receivedRegionCount == 1)
        #expect(response.geofences.isEmpty)
        let api = GeofenceApiServiceMock()
        api.fetchNearbyGeofencesClosure = { _, _, completion in completion(.success(response)) }

        let setup = makeCoordinator(api: api, storage: storage)
        let result = await setup.coordinator.refresh(latitude: 37.7749, longitude: -122.4194)

        #expect(result.errorOrNil == .fetchFailed(.decoding))
        #expect(await storage.getCachedGeofences().map(\.id) == ["kept"])
    }

    /// A workspace whose fences have all moved to a shape this SDK cannot monitor is the opposite
    /// of a broken payload: the response read fine and there is genuinely nothing here for us.
    /// Failing would freeze the previous fences in place with a refresh that can never succeed.
    @Test
    func refresh_givenEveryRegionAnUnsupportedShape_expectAppliedAsEmpty() async {
        let storage = makeStorage()
        await storage.setCachedGeofences([makeRegion(id: "stale", latitude: 37.7749, longitude: -122.4194)])
        let futureShape = GeofenceApiRegion(
            id: "future", name: nil, shape: "corridor",
            latitude: 37.7749, longitude: -122.4194, radius: 100,
            geometry: nil, enclosingCircle: nil, externalId: nil,
            transitionTypes: nil, lastUpdated: nil, geosetIds: nil, metadata: nil
        )
        let api = GeofenceApiServiceMock()
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            completion(.success(GeofenceApiResponse(config: nil, geofences: [futureShape])))
        }

        let setup = makeCoordinator(api: api, storage: storage)
        let result = await setup.coordinator.refresh(latitude: 37.7749, longitude: -122.4194)

        #expect(result.errorOrNil == nil)
        #expect(await storage.getCachedGeofences().isEmpty)
    }

    @Test
    func refresh_givenEmptyServerResponse_expectMovementTriggerStillRegistered() async {
        let storage = makeStorage()
        let api = GeofenceApiServiceMock()
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            completion(.success(makeApiResponse(regions: [])))
        }

        let setup = makeCoordinator(api: api, storage: storage)
        _ = await setup.coordinator.refresh(latitude: 37.7749, longitude: -122.4194)

        // Empty nearby response is a geofence-free area, not a stop signal: keep the movement trigger
        // armed so a later EXIT re-fetches as the device moves back toward geofences. The trigger is
        // the only region registered (no business geofences to add).
        #expect(setup.monitor.startedRegions.map(\.identifier) == [GeofenceConstants.movementTriggerIdentifier])
    }

    @Test
    func refresh_givenEmptyServerResponseButKillSwitch_expectNothingRegistered() async {
        // maxBusinessGeofences == 0 is the runtime off switch: even with the "keep monitoring
        // through empty areas" behavior, a kill-switched account registers nothing at all.
        let storage = makeStorage()
        let config = GeofenceConfig(
            localRefreshTriggerRadius: 750,
            remoteFetchRefreshTriggerRadius: 3000,
            remoteFetchRefreshExpiry: 86400,
            duplicateEventsExpiry: 60,
            maxBusinessGeofences: 0,
            maxMonitoringDistance: GeofenceConstants.noMonitoringDistanceCap
        )
        await storage.setCachedConfig(config)
        let api = GeofenceApiServiceMock()
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            completion(.success(makeApiResponse(regions: [], config: config)))
        }

        let setup = makeCoordinator(api: api, storage: storage)
        _ = await setup.coordinator.refresh(latitude: 37.7749, longitude: -122.4194)

        #expect(setup.monitor.startedRegions.isEmpty)
    }

    @Test
    func refresh_givenSuccess_expectMovementTriggerRegisteredBeforeBusinessRegions() async {
        let storage = makeStorage()
        let api = GeofenceApiServiceMock()
        let region = makeRegion(id: "g1", latitude: 1.0, longitude: 2.0)
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            completion(.success(makeApiResponse(regions: [region])))
        }

        let setup = makeCoordinator(api: api, storage: storage)
        _ = await setup.coordinator.refresh(latitude: 1.0, longitude: 2.0)

        // The trigger goes first so it isn't starved when business regions fill the shared OS budget.
        // Nothing was registered before, so nothing is stopped.
        #expect(setup.monitor.operationLog == [
            .start(identifier: GeofenceConstants.movementTriggerIdentifier),
            .start(identifier: "g1")
        ])
    }

    // MARK: - Concurrency

    @Test
    func refresh_givenConcurrentCalls_expectSecondReturnsAlreadyInProgress() async {
        let storage = makeStorage()
        let api = GeofenceApiServiceMock()
        let firstReachedApi = AsyncSignal()
        let allowFinish = AsyncSignal()
        api.fetchNearbyGeofencesClosure = { _, _, completion in
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
        #expect(api.fetchNearbyGeofencesCallsCount == 1)
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
        api.fetchNearbyGeofencesClosure = { _, _, completion in
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
        api.fetchNearbyGeofencesClosure = { _, _, completion in
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
        api.fetchNearbyGeofencesClosure = { _, _, completion in
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

    /// Cold-wake sibling of the refresh rule: bootstrap persists whatever this returns, so an
    /// oversized polygon reported here would be evaluated for membership with no OS wake behind it.
    @Test
    func applyCachedRegistration_givenOversizedPolygon_expectExcludedFromReportedRegistration() {
        let monitor = MockGeofenceRegionMonitor()
        monitor.maximumMonitoringRadius = 1000
        let setup = makeCoordinator(storage: makeStorage(), monitor: monitor)
        let oversizedPolygon = Geofence(
            id: "poly", latitude: 0, longitude: 0, radius: 5000, name: nil,
            transitionTypes: [.enter, .exit], lastUpdated: Date(timeIntervalSince1970: 0),
            vertices: [
                LocationData(latitude: -0.01, longitude: -0.01),
                LocationData(latitude: -0.01, longitude: 0.01),
                LocationData(latitude: 0.01, longitude: 0.01),
                LocationData(latitude: 0.01, longitude: -0.01)
            ]
        )
        let circle = Geofence(
            id: "circle", latitude: 0, longitude: 0, radius: 100, name: nil,
            transitionTypes: [.enter, .exit], lastUpdated: Date(timeIntervalSince1970: 0)
        )

        let registration = setup.coordinator.applyCachedRegistration(
            cachedRegions: [oversizedPolygon, circle],
            anchor: LocationData(latitude: 0, longitude: 0),
            config: .fallback,
            userId: "user-1"
        )

        #expect(registration?.businessIds.contains("poly") == false)
        #expect(registration?.businessIds.contains("circle") == true)
    }

    @Test
    func applyCachedRegistration_givenEmptyRegions_expectMovementTriggerRegistered() {
        // An empty nearby response clears the cache but leaves the trigger armed. If the OS then
        // drops our regions, this is the only path that re-arms it — the refresh decision skips on
        // a cache that is fresh and empty.
        let setup = makeCoordinator(storage: makeStorage())

        let registration = setup.coordinator.applyCachedRegistration(
            cachedRegions: [],
            anchor: LocationData(latitude: 0, longitude: 0),
            config: .fallback,
            userId: "user-1"
        )

        #expect(setup.monitor.startedRegions.map(\.identifier) == [GeofenceConstants.movementTriggerIdentifier])
        #expect(registration?.businessIds.isEmpty == true)
    }

    @Test
    func applyCachedRegistration_givenEmptyRegionsAndKillSwitch_expectNothingRegistered() {
        // The kill switch still wins over the empty-cache restore above.
        let config = GeofenceConfig(
            localRefreshTriggerRadius: 750,
            remoteFetchRefreshTriggerRadius: 3000,
            remoteFetchRefreshExpiry: 86400,
            duplicateEventsExpiry: 60,
            maxBusinessGeofences: 0,
            maxMonitoringDistance: GeofenceConstants.noMonitoringDistanceCap
        )
        let setup = makeCoordinator(storage: makeStorage())

        _ = setup.coordinator.applyCachedRegistration(
            cachedRegions: [],
            anchor: LocationData(latitude: 0, longitude: 0),
            config: config,
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
        api.fetchNearbyGeofencesClosure = { _, _, completion in
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
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            completion(.success(makeApiResponse(regions: [])))
        }
        let setup = makeCoordinator(api: api, storage: storage, contextStore: contextStore)

        let first = await setup.coordinator.refresh(latitude: 1.0, longitude: 2.0)
        #expect(first.errorOrNil == .noIdentifiedUser)

        // User signs in between calls.
        contextStore.setUserId("user-1")
        let second = await setup.coordinator.refresh(latitude: 1.0, longitude: 2.0)

        #expect(second.isSuccess)
        #expect(api.fetchNearbyGeofencesCallsCount == 1)
    }

    // MARK: - handleMovement

    @Test
    func handleMovement_givenNoUserId_expectFailureAndNoApiCall() async {
        let storage = makeStorage()
        let setup = makeCoordinator(storage: storage, contextStore: makeContextStore(userId: nil))

        let result = await setup.coordinator.handleMovement(latitude: 1.0, longitude: 2.0)

        #expect(result.errorOrNil == .noIdentifiedUser)
        #expect(setup.api.fetchNearbyGeofencesCallsCount == 0)
        #expect(setup.monitor.startedRegions.isEmpty)
    }

    @Test
    func handleMovement_givenNoAnchor_expectTierBRemoteFetch() async {
        // No prior sync → no anchor → can't distance-compare, so default to remote fetch.
        // Matches Android's `anchor == null` branch.
        let storage = makeStorage()
        let api = GeofenceApiServiceMock()
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            completion(.success(makeApiResponse(regions: [makeRegion(id: "g1", latitude: 0, longitude: 0)])))
        }
        let setup = makeCoordinator(api: api, storage: storage)

        let result = await setup.coordinator.handleMovement(latitude: 1.0, longitude: 2.0)

        #expect(result.isSuccess)
        #expect(setup.api.fetchNearbyGeofencesCallsCount == 1)
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
        #expect(setup.api.fetchNearbyGeofencesCallsCount == 0)
        let businessRegistered = setup.monitor.startedRegions.filter { $0.identifier != GeofenceConstants.movementTriggerIdentifier }
        #expect(businessRegistered.map(\.identifier) == ["near", "far"])
    }

    @Test
    func handleMovement_givenLocalRerankWithEmptyCache_expectMovementTriggerStillRegistered() async {
        // After an empty nearby response wiped the cache, a within-threshold EXIT re-ranks an empty
        // set. The movement trigger must stay armed (re-centered at the new location) so the device
        // keeps moving toward the next refetch instead of going dark in a geofence-free area.
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
        await storage.setCachedGeofences([]) // wiped by a prior empty response
        let api = GeofenceApiServiceMock()
        let setup = makeCoordinator(api: api, storage: storage)

        // ~111 m from anchor — within the refetch radius, so it re-ranks locally, no fetch.
        let result = await setup.coordinator.handleMovement(latitude: 0, longitude: 0.001)

        #expect(result.isSuccess)
        #expect(setup.api.fetchNearbyGeofencesCallsCount == 0)
        let trigger = setup.monitor.startedRegions.first { $0.identifier == GeofenceConstants.movementTriggerIdentifier }
        #expect(trigger?.center == LocationData(latitude: 0, longitude: 0.001))
    }

    @Test
    func handleMovement_givenMovementBeyondThreshold_expectRemoteFetch() async {
        // A move beyond the refetch radius from the last fetch anchor leaves the cached nearby set no
        // longer covering the area, so it refetches a fresh nearby set.
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
        let api = GeofenceApiServiceMock()
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            completion(.success(makeApiResponse(regions: [makeRegion(id: "g1", latitude: 1, longitude: 1)])))
        }
        let setup = makeCoordinator(api: api, storage: storage)

        // ~157 km from anchor — beyond the 5 km refetch radius.
        let result = await setup.coordinator.handleMovement(latitude: 1.0, longitude: 1.0)

        #expect(result.isSuccess)
        #expect(setup.api.fetchNearbyGeofencesCallsCount == 1)
    }

    @Test
    func refresh_givenMovedBeyondRefetchRadius_expectRemoteFetch() async {
        // Time-fresh, but the device moved beyond the refetch radius from the last fetch anchor, so
        // the cached nearby set no longer covers the area and it refetches.
        let storage = makeStorage()
        let dateUtil = DateUtilStub()
        dateUtil.givenNow = Date(timeIntervalSince1970: 1000)
        let config = GeofenceConfig(
            localRefreshTriggerRadius: 1000,
            remoteFetchRefreshTriggerRadius: 5000,
            remoteFetchRefreshExpiry: 3600,
            duplicateEventsExpiry: 3600,
            maxBusinessGeofences: 10,
            maxMonitoringDistance: GeofenceConstants.noMonitoringDistanceCap
        )
        await storage.setCachedConfig(config)
        // Fetched recently (time-fresh) at (0, 0).
        await storage.recordSync(timestamp: dateUtil.givenNow.addingTimeInterval(-100), location: LocationData(latitude: 0, longitude: 0))
        let api = GeofenceApiServiceMock()
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            completion(.success(makeApiResponse(regions: [makeRegion(id: "g1", latitude: 1, longitude: 1)])))
        }
        let setup = makeCoordinator(api: api, storage: storage, dateUtil: dateUtil)

        // ~157 km from the fetch anchor — beyond the 5 km refetch radius.
        let result = await setup.coordinator.refresh(latitude: 1.0, longitude: 1.0)

        #expect(result.isSuccess)
        #expect(setup.api.fetchNearbyGeofencesCallsCount == 1)
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
    func handleMovement_givenRemoteFetchFails_expectMovementTriggerRearmedAtCurrentFix() async {
        // A failed pass leaves the trigger on the circle the device just exited, so no further EXIT
        // can fire and re-ranking stops until the next launch. Re-rank from cache to re-arm it.
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
        let fetchAnchor = LocationData(latitude: 0, longitude: 0)
        await storage.recordSync(timestamp: Date(timeIntervalSince1970: 100), location: fetchAnchor)
        let api = GeofenceApiServiceMock()
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            completion(.failure(.transport))
        }
        let setup = makeCoordinator(api: api, storage: storage)

        // ~157 km from the anchor — beyond the 5 km refetch radius, so this takes the remote tier.
        let newLocation = LocationData(latitude: 1.0, longitude: 1.0)
        let result = await setup.coordinator.handleMovement(latitude: newLocation.latitude, longitude: newLocation.longitude)

        // The fetch failure is still what the caller sees.
        #expect(result.errorOrNil == .fetchFailed(.transport))
        #expect(setup.api.fetchNearbyGeofencesCallsCount == 1)
        // ...but the trigger now sits on the device's current fix, so movement can fire again.
        let movementTrigger = setup.monitor.startedRegions.last { $0.identifier == GeofenceConstants.movementTriggerIdentifier }
        #expect(movementTrigger?.center == newLocation)
        #expect(movementTrigger?.radius == config.localRefreshTriggerRadius)
        // The fetch anchor stays put, so the next EXIT retries remotely instead of treating the
        // re-arm as a successful sync.
        #expect(await storage.getLastSync()?.location == fetchAnchor)
    }

    @Test
    func handleMovement_givenRemoteFetchFailsUnderKillSwitch_expectTeardownNotRearm() async {
        // The re-arm fallback must not resurrect the trigger the kill switch just tore down.
        let storage = makeStorage()
        let config = GeofenceConfig(
            localRefreshTriggerRadius: 1000,
            remoteFetchRefreshTriggerRadius: 5000,
            remoteFetchRefreshExpiry: 3600,
            duplicateEventsExpiry: 3600,
            maxBusinessGeofences: 0,
            maxMonitoringDistance: GeofenceConstants.noMonitoringDistanceCap
        )
        await storage.setCachedConfig(config)
        await storage.recordSync(timestamp: Date(timeIntervalSince1970: 100), location: LocationData(latitude: 0, longitude: 0))
        let api = GeofenceApiServiceMock()
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            completion(.failure(.transport))
        }
        let setup = makeCoordinator(api: api, storage: storage)

        let result = await setup.coordinator.handleMovement(latitude: 1.0, longitude: 1.0)

        #expect(result.errorOrNil == .fetchFailed(.transport))
        #expect(setup.monitor.monitoredRegionIdentifiers.isEmpty)
        #expect(!setup.monitor.startedRegions.contains { $0.identifier == GeofenceConstants.movementTriggerIdentifier })
    }

    // MARK: unchanged-set fast path (crossing absorption)

    /// Shared arrangement for the registration-diff tests: an initial remote refresh registers
    /// `regions`, so the monitor owns them and the OS holds them — the steady state every
    /// subsequent re-rank runs against.
    private func makeRegisteredSetup(
        regions: [Geofence],
        config: GeofenceConfig,
        storage: GeofenceStorage
    ) async -> Setup {
        let api = GeofenceApiServiceMock()
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            completion(.success(makeApiResponse(regions: regions, config: config)))
        }
        let setup = makeCoordinator(api: api, storage: storage)
        _ = await setup.coordinator.refresh(latitude: 0, longitude: 0)
        return setup
    }

    private var diffConfig: GeofenceConfig {
        GeofenceConfig(
            localRefreshTriggerRadius: 1000,
            remoteFetchRefreshTriggerRadius: 5000,
            remoteFetchRefreshExpiry: 3600,
            duplicateEventsExpiry: 3600,
            maxBusinessGeofences: 10,
            maxMonitoringDistance: GeofenceConstants.noMonitoringDistanceCap
        )
    }

    @Test
    func handleMovement_givenRerankLandsOnSameNearestSet_expectBusinessRegionsUntouched() async {
        // Steady-state drive: adjacent trigger EXITs mostly land on the identical nearest set.
        // Re-registering re-seeds the OS's assumed state and absorbs an undelivered crossing, so the
        // business regions must be left alone — only the trigger re-centers.
        //
        // 111 m is inside the re-rank radius, so this takes the cheap polygon wake pass: the wake
        // re-arms at the new position but the ranking anchor must NOT walk. Walking it on every
        // wake would reset the distance re-ranking is measured against, and re-ranking would never
        // come due — see `handleMovement_givenMoveBeyondRerankRadius_expectAnchorWalks`.
        let region = makeRegion(id: "g1", latitude: 0.5, longitude: 0.5)
        let storage = makeStorage()
        let setup = await makeRegisteredSetup(regions: [region], config: diffConfig, storage: storage)

        // ~111 m: within the refetch radius → local re-rank, same nearest set.
        let newLocation = LocationData(latitude: 0, longitude: 0.001)
        let result = await setup.coordinator.handleMovement(latitude: newLocation.latitude, longitude: newLocation.longitude)

        #expect(result.isSuccess)
        #expect(setup.monitor.stopAllCallCount == 0)
        #expect(setup.monitor.startedRegions.filter { $0.identifier == "g1" }.count == 1) // never re-added
        #expect(setup.monitor.stoppedIdentifiers == [GeofenceConstants.movementTriggerIdentifier])
        let triggerStarts = setup.monitor.startedRegions.filter { $0.identifier == GeofenceConstants.movementTriggerIdentifier }
        #expect(triggerStarts.count == 2)
        #expect(triggerStarts.last?.center == newLocation)
        #expect(await storage.getLastRegistrationCenter() == LocationData(latitude: 0, longitude: 0))
    }

    /// The launch/identify refresh anchors on the STORED registration centre, not a live fix, so a
    /// boundary-sized trigger there would be a small circle around a point the device may be far
    /// from — spurious on 17+, and never fired at all on the classic path. Only a caller holding a
    /// real fix gets the tight radius.
    @Test
    func refresh_givenNearbyPolygonButStoredAnchor_expectFullRefreshRadius() async {
        let ring = [
            LocationData(latitude: -0.0018, longitude: -0.0018),
            LocationData(latitude: -0.0018, longitude: 0.0018),
            LocationData(latitude: 0.0018, longitude: 0.0018),
            LocationData(latitude: 0.0018, longitude: -0.0018)
        ]
        let polygon = Geofence(
            id: "poly", latitude: 0, longitude: 0, radius: 500, name: "poly",
            transitionTypes: [.enter, .exit], lastUpdated: Date(timeIntervalSince1970: 1700000000),
            vertices: ring
        )
        let storage = makeStorage()
        let setup = await makeRegisteredSetup(regions: [polygon], config: diffConfig, storage: storage)
        let before = setup.monitor.startedRegions.count
        // Age the sync so the refresh actually re-registers rather than taking the freshness skip.
        await storage.recordSync(timestamp: Date(timeIntervalSince1970: 0), location: LocationData(latitude: 0, longitude: 0))

        _ = await setup.coordinator.refresh(latitude: 0, longitude: 0.001, anchorIsLiveFix: false)

        let trigger = setup.monitor.startedRegions.dropFirst(before)
            .last { $0.identifier == GeofenceConstants.movementTriggerIdentifier }
        #expect(trigger?.radius == diffConfig.localRefreshTriggerRadius, "got \(String(describing: trigger?.radius))")
    }

    /// Control for the above: the same refresh from a caller that does hold a fix still tightens.
    @Test
    func refresh_givenNearbyPolygonAndLiveAnchor_expectTriggerShrunkToItsBoundary() async {
        let ring = [
            LocationData(latitude: -0.0018, longitude: -0.0018),
            LocationData(latitude: -0.0018, longitude: 0.0018),
            LocationData(latitude: 0.0018, longitude: 0.0018),
            LocationData(latitude: 0.0018, longitude: -0.0018)
        ]
        let polygon = Geofence(
            id: "poly", latitude: 0, longitude: 0, radius: 500, name: "poly",
            transitionTypes: [.enter, .exit], lastUpdated: Date(timeIntervalSince1970: 1700000000),
            vertices: ring
        )
        let storage = makeStorage()
        let setup = await makeRegisteredSetup(regions: [polygon], config: diffConfig, storage: storage)
        let before = setup.monitor.startedRegions.count
        // Age the sync so the refresh actually re-registers rather than taking the freshness skip.
        await storage.recordSync(timestamp: Date(timeIntervalSince1970: 0), location: LocationData(latitude: 0, longitude: 0))

        _ = await setup.coordinator.refresh(latitude: 0, longitude: 0.001, anchorIsLiveFix: true)

        let trigger = setup.monitor.startedRegions.dropFirst(before)
            .last { $0.identifier == GeofenceConstants.movementTriggerIdentifier }
        #expect(trigger?.radius == GeofenceConstants.polygonWakeMinRadius, "got \(String(describing: trigger?.radius))")
    }

    @Test
    func handleMovement_givenNearbyPolygon_expectTriggerShrunkToItsBoundary() async {
        // The end-to-end assertion behind `PolygonWakeRadius`: a polygon the device stands inside
        // must actually shrink the trigger the OS is given, not just the value the helper returns.
        let ring = [
            LocationData(latitude: -0.0018, longitude: -0.0018),
            LocationData(latitude: -0.0018, longitude: 0.0018),
            LocationData(latitude: 0.0018, longitude: 0.0018),
            LocationData(latitude: 0.0018, longitude: -0.0018)
        ]
        let polygon = Geofence(
            id: "poly", latitude: 0, longitude: 0, radius: 500, name: "poly",
            transitionTypes: [.enter, .exit], lastUpdated: Date(timeIntervalSince1970: 1700000000),
            vertices: ring
        )
        let storage = makeStorage()
        let setup = await makeRegisteredSetup(regions: [polygon], config: diffConfig, storage: storage)

        // ~111 m east of centre: still ~89 m from the eastern edge, so the floor should win.
        _ = await setup.coordinator.handleMovement(latitude: 0, longitude: 0.001)

        let trigger = setup.monitor.startedRegions
            .last { $0.identifier == GeofenceConstants.movementTriggerIdentifier }
        #expect(trigger?.radius == GeofenceConstants.polygonWakeMinRadius, "got \(String(describing: trigger?.radius))")
        // And the circle-only control: no polygon means the configured radius, untouched.
        let circleStorage = makeStorage()
        let circleSetup = await makeRegisteredSetup(
            regions: [makeRegion(id: "c1", latitude: 0, longitude: 0)], config: diffConfig, storage: circleStorage
        )
        _ = await circleSetup.coordinator.handleMovement(latitude: 0, longitude: 0.001)
        let circleTrigger = circleSetup.monitor.startedRegions
            .last { $0.identifier == GeofenceConstants.movementTriggerIdentifier }
        #expect(circleTrigger?.radius == diffConfig.localRefreshTriggerRadius)
    }

    @Test
    func handleMovement_givenMoveBeyondRerankRadius_expectAnchorWalks() async {
        // The other side of the gate: past the re-rank radius the full pass runs and the ranking
        // anchor moves, so the cheap-pass short-circuit cannot starve re-ranking.
        let region = makeRegion(id: "g1", latitude: 0.5, longitude: 0.5)
        let storage = makeStorage()
        let setup = await makeRegisteredSetup(regions: [region], config: diffConfig, storage: storage)

        // ~1.7 km east: beyond localRefreshTriggerRadius (1000 m), inside the refetch radius.
        let newLocation = LocationData(latitude: 0, longitude: 0.015)
        let result = await setup.coordinator.handleMovement(latitude: newLocation.latitude, longitude: newLocation.longitude)

        #expect(result.isSuccess)
        #expect(await storage.getLastRegistrationCenter() == newLocation)
    }

    @Test
    func handleMovement_givenEmptyAreaThenKillSwitch_expectTriggerStopped() async {
        // A geofence-free area leaves the trigger armed with no business regions, so a later
        // kill-switched config re-ranks onto the same (empty) business set. The desired set is empty
        // too, so the diff must stop the trigger rather than re-center it.
        let storage = makeStorage()
        let setup = await makeRegisteredSetup(regions: [], config: diffConfig, storage: storage)
        #expect(setup.monitor.monitoredRegionIdentifiers == [GeofenceConstants.movementTriggerIdentifier])

        await storage.setCachedConfig(GeofenceConfig(
            localRefreshTriggerRadius: 1000,
            remoteFetchRefreshTriggerRadius: 5000,
            remoteFetchRefreshExpiry: 3600,
            duplicateEventsExpiry: 3600,
            maxBusinessGeofences: 0,
            maxMonitoringDistance: GeofenceConstants.noMonitoringDistanceCap
        ))

        let result = await setup.coordinator.handleMovement(latitude: 0, longitude: 0.001)

        #expect(result.isSuccess)
        #expect(setup.monitor.stoppedIdentifiers == [GeofenceConstants.movementTriggerIdentifier])
        #expect(setup.monitor.monitoredRegionIdentifiers.isEmpty)
    }

    @Test
    func handleMovement_givenRerankChangesNearestSet_expectOnlyDepartingRegionStopped() async {
        // Membership actually changed (budget of 1, a closer fence took the slot) — the departing
        // region is stopped and the arriving one started, so the OS set matches the new ranking.
        let config = GeofenceConfig(
            localRefreshTriggerRadius: 1000,
            remoteFetchRefreshTriggerRadius: 5000,
            remoteFetchRefreshExpiry: 3600,
            duplicateEventsExpiry: 3600,
            maxBusinessGeofences: 1,
            maxMonitoringDistance: GeofenceConstants.noMonitoringDistanceCap
        )
        let nearStart = makeRegion(id: "near-start", latitude: 0, longitude: 0.001)
        let nearEnd = makeRegion(id: "near-end", latitude: 0, longitude: 0.021)
        let setup = await makeRegisteredSetup(regions: [nearStart, nearEnd], config: config, storage: makeStorage())

        // ~2.2 km: still a local re-rank, but the single budget slot now belongs to near-end.
        let result = await setup.coordinator.handleMovement(latitude: 0, longitude: 0.02)

        #expect(result.isSuccess)
        #expect(setup.monitor.stopAllCallCount == 0)
        #expect(setup.monitor.startedRegions.contains { $0.identifier == "near-end" })
        #expect(setup.monitor.stoppedIdentifiers.contains("near-start"))
        #expect(setup.monitor.monitoredRegionIdentifiers == ["near-end", GeofenceConstants.movementTriggerIdentifier])
    }

    @Test
    func handleMovement_givenSetChanges_expectCarryOverRegionLeftRegistered() async {
        // A re-rank that changes membership must leave regions present in both sets completely
        // untouched: stopping and re-adding one discards any crossing the OS has detected but not
        // yet delivered, and neither monitor replays it.
        let config = GeofenceConfig(
            localRefreshTriggerRadius: 1000,
            remoteFetchRefreshTriggerRadius: 5000,
            remoteFetchRefreshExpiry: 3600,
            duplicateEventsExpiry: 3600,
            maxBusinessGeofences: 2,
            maxMonitoringDistance: GeofenceConstants.noMonitoringDistanceCap
        )
        let carry = makeRegion(id: "carry", latitude: 0, longitude: 0.001)
        let leaves = makeRegion(id: "leaves", latitude: 0, longitude: -0.002)
        let joins = makeRegion(id: "joins", latitude: 0, longitude: 0.021)
        let setup = await makeRegisteredSetup(regions: [carry, leaves, joins], config: config, storage: makeStorage())
        #expect(setup.monitor.monitoredRegionIdentifiers == ["carry", "leaves", GeofenceConstants.movementTriggerIdentifier])

        // ~2.2 km east: local re-rank. `joins` takes the slot `leaves` gives up; `carry` stays.
        let result = await setup.coordinator.handleMovement(latitude: 0, longitude: 0.02)

        #expect(result.isSuccess)
        #expect(setup.monitor.monitoredRegionIdentifiers == ["carry", "joins", GeofenceConstants.movementTriggerIdentifier])
        #expect(!setup.monitor.stoppedIdentifiers.contains("carry"))
        #expect(setup.monitor.startedRegions.filter { $0.identifier == "carry" }.count == 1)
        #expect(setup.monitor.stoppedIdentifiers.contains("leaves"))
        #expect(setup.monitor.startedRegions.contains { $0.identifier == "joins" })
    }

    @Test
    func handleMovement_givenRadiusAboveOsCap_expectNoReRegistrationChurn() async {
        // The OS clamps every radius to `maximumMonitoringRadius`. The unchanged check must compare
        // against that clamped radius, or an over-cap region reads as changed on every pass and
        // re-registers forever.
        let monitor = MockGeofenceRegionMonitor()
        monitor.maximumMonitoringRadius = 500
        let storage = makeStorage()
        let api = GeofenceApiServiceMock()
        let region = makeRegion(id: "wide", latitude: 0, longitude: 0.001, radius: 2000)
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            completion(.success(makeApiResponse(regions: [region], config: diffConfig)))
        }
        let setup = makeCoordinator(api: api, storage: storage, monitor: monitor)
        _ = await setup.coordinator.refresh(latitude: 0, longitude: 0)

        let result = await setup.coordinator.handleMovement(latitude: 0, longitude: 0.001)

        #expect(result.isSuccess)
        #expect(!setup.monitor.stoppedIdentifiers.contains("wide"))
        #expect(setup.monitor.startedRegions.filter { $0.identifier == "wide" }.count == 1)
    }

    @Test
    func handleMovement_givenUnchangedSetButOsDroppedRegion_expectRegionReRegistered() async {
        // The identifier is still owned in-process but the OS silently dropped it (monitoring
        // failure). The diff must not trust ownership alone — re-registering is what heals it.
        let region = makeRegion(id: "g1", latitude: 0.5, longitude: 0.5)
        let setup = await makeRegisteredSetup(regions: [region], config: diffConfig, storage: makeStorage())
        setup.monitor.osMonitoredRegions.remove("g1")

        let result = await setup.coordinator.handleMovement(latitude: 0, longitude: 0.001)

        #expect(result.isSuccess)
        #expect(setup.monitor.stopAllCallCount == 0)
        #expect(setup.monitor.startedRegions.filter { $0.identifier == "g1" }.count == 2)
    }

    @Test
    func refresh_givenOsHoldsUnownedRegionNoLongerNearest_expectSweptFromOs() async {
        // A condition the OS still holds from a previous launch that this process never adopted and
        // the server no longer returns. Ownership-based teardown can't see it, so only the sweep
        // against live OS state removes it — otherwise it keeps one of the 20 slots indefinitely.
        let storage = makeStorage()
        let dateUtil = DateUtilStub()
        await storage.setCachedConfig(diffConfig)
        await storage.recordSync(timestamp: dateUtil.givenNow.addingTimeInterval(-100), location: LocationData(latitude: 0, longitude: 0))
        await storage.setCachedGeofences([makeRegion(id: "g1", latitude: 0.001, longitude: 0, radius: 500)])
        let setup = makeCoordinator(storage: storage, dateUtil: dateUtil)
        setup.monitor.seedOsHeldRegion(
            identifier: "stranded",
            center: LocationData(latitude: 5, longitude: 5),
            radius: 300,
            transitionTypes: [.enter, .exit]
        )

        _ = await setup.coordinator.refresh(latitude: 0, longitude: 0)

        #expect(!setup.monitor.osMonitoredRegions.contains("stranded"))
        #expect(setup.monitor.osMonitoredRegions.contains("g1"))
    }

    @Test
    func refresh_givenAdoptedRegionsWithPersistedGeometry_expectUnchangedRegionLeftUntouched() async {
        // Cold launch on the CLMonitor path: the OS still holds last session's condition and the
        // persisted record carries its geometry, which adoption seeds synchronously. A sync landing
        // before the queued re-arm drains must read the unchanged region as unchanged — re-adding
        // it would absorb a crossing the OS has detected but not yet delivered.
        let storage = makeStorage()
        let dateUtil = DateUtilStub()
        await storage.setCachedConfig(diffConfig)
        await storage.recordSync(timestamp: dateUtil.givenNow.addingTimeInterval(-100), location: LocationData(latitude: 0, longitude: 0))
        await storage.setCachedGeofences([makeRegion(id: "g1", latitude: 0.001, longitude: 0, radius: 500)])
        let setup = makeCoordinator(storage: storage, dateUtil: dateUtil)
        setup.monitor.osMonitoredRegions = ["g1"]
        setup.monitor.adoptExistingRegions(
            matching: ["g1"],
            records: [
                "g1": MonitorRegionRecord(
                    lastState: .enter,
                    transitionTypes: [.enter, .exit],
                    center: LocationData(latitude: 0.001, longitude: 0),
                    radius: 500,
                    lastStateChangedAt: nil
                )
            ]
        )

        _ = await setup.coordinator.refresh(latitude: 0, longitude: 0)

        #expect(!setup.monitor.stoppedIdentifiers.contains("g1"))
        #expect(setup.monitor.startedRegions.filter { $0.identifier == "g1" }.isEmpty)
        #expect(setup.monitor.monitoredRegionIdentifiers.contains("g1"))
    }

    @Test
    func refresh_givenFreshProcessAndReshapedRegionOsStillHolds_expectOsGeometryUpdated() async {
        // Fresh process owning nothing, OS still holding `g1` from the previous launch on its old
        // circle, and the server has since reshaped it. CLMonitor silently ignores an add over a
        // live identifier, so without an explicit removal the OS keeps the old circle while this
        // process records the new one — every later pass then reads "unchanged" and never repairs
        // it. The stale circle would outlive the process indefinitely.
        let storage = makeStorage()
        let dateUtil = DateUtilStub()
        await storage.setCachedConfig(diffConfig)
        await storage.recordSync(timestamp: dateUtil.givenNow.addingTimeInterval(-100), location: LocationData(latitude: 0, longitude: 0))
        await storage.recordRegistration(center: LocationData(latitude: 0, longitude: 0), businessIds: ["g1"])
        await storage.setCachedGeofences([makeRegion(id: "g1", latitude: 0.5, longitude: 0.5, radius: 750)])
        let setup = makeCoordinator(storage: storage, dateUtil: dateUtil)
        setup.monitor.osMonitoredRegions = [GeofenceConstants.movementTriggerIdentifier]
        setup.monitor.seedOsHeldRegion(
            identifier: "g1",
            center: LocationData(latitude: 0.5, longitude: 0.5),
            radius: 100, // the OLD circle
            transitionTypes: [.enter, .exit]
        )

        let result = await setup.coordinator.refresh(latitude: 0.02, longitude: 0)

        #expect(result.isSuccess)
        #expect(setup.monitor.osGeometry(for: "g1")?.radius == 750)
    }

    @Test
    func refresh_givenFreshProcessWithMatchingStorage_expectRegionsRegistered() async {
        // Fresh process: storage says the same set is registered and the OS still holds it, but this
        // process owns nothing yet (bootstrap hasn't adopted). Skipping would leave OS events with no
        // owner — everything must be registered to re-establish in-process ownership.
        let storage = makeStorage()
        let dateUtil = DateUtilStub()
        await storage.setCachedConfig(diffConfig)
        await storage.recordSync(timestamp: dateUtil.givenNow.addingTimeInterval(-100), location: LocationData(latitude: 0, longitude: 0))
        await storage.recordRegistration(center: LocationData(latitude: 0, longitude: 0), businessIds: ["g1"])
        await storage.setCachedGeofences([makeRegion(id: "g1", latitude: 0.5, longitude: 0.5)])
        let setup = makeCoordinator(storage: storage, dateUtil: dateUtil)
        setup.monitor.osMonitoredRegions = ["g1", GeofenceConstants.movementTriggerIdentifier]

        // ~2.2 km from the registration center → ranking stale → local re-rank, same nearest set.
        let result = await setup.coordinator.refresh(latitude: 0.02, longitude: 0)

        #expect(result.isSuccess)
        #expect(setup.monitor.stopAllCallCount == 0)
        #expect(setup.monitor.startedRegions.contains { $0.identifier == "g1" })
        #expect(setup.monitor.monitoredRegionIdentifiers == ["g1", GeofenceConstants.movementTriggerIdentifier])
    }

    @Test
    func handleMovement_givenRemoteRefreshReturnsIdenticalPayload_expectBusinessRegionsUntouched() async {
        // The 5 km refetch fired but the server returned byte-identical data and the ranking didn't
        // change — same absorption risk as the local case. The trigger and both anchors must still
        // walk forward so the next refetch threshold measures from here.
        let region = makeRegion(id: "g1", latitude: 0.5, longitude: 0.5)
        let storage = makeStorage()
        let setup = await makeRegisteredSetup(regions: [region], config: diffConfig, storage: storage)

        // ~5.5 km from the fetch anchor → remote tier.
        let newLocation = LocationData(latitude: 0, longitude: 0.05)
        let result = await setup.coordinator.handleMovement(latitude: newLocation.latitude, longitude: newLocation.longitude)

        #expect(result.isSuccess)
        #expect(setup.api.fetchNearbyGeofencesCallsCount == 2)
        #expect(setup.monitor.stopAllCallCount == 0)
        #expect(setup.monitor.startedRegions.filter { $0.identifier == "g1" }.count == 1)
        let triggerStarts = setup.monitor.startedRegions.filter { $0.identifier == GeofenceConstants.movementTriggerIdentifier }
        #expect(triggerStarts.last?.center == newLocation)
        #expect(await storage.getLastSync()?.location == newLocation)
        #expect(await storage.getLastRegistrationCenter() == newLocation)
    }

    @Test
    func handleMovement_givenRemoteRefreshChangesGeometry_expectRegionReRegistered() async {
        // Same id, but the server edited the fence (radius change) — the geometry compare must catch
        // it and re-register, or the OS keeps monitoring the old circle forever.
        let original = makeRegion(id: "g1", latitude: 0.5, longitude: 0.5, radius: 100)
        let resized = makeRegion(id: "g1", latitude: 0.5, longitude: 0.5, radius: 250)
        let config = diffConfig
        let api = GeofenceApiServiceMock()
        var responses = [[original], [resized]]
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            completion(.success(makeApiResponse(regions: responses.removeFirst(), config: config)))
        }
        let setup = makeCoordinator(api: api, storage: makeStorage())
        _ = await setup.coordinator.refresh(latitude: 0, longitude: 0)

        let result = await setup.coordinator.handleMovement(latitude: 0, longitude: 0.05)

        #expect(result.isSuccess)
        #expect(setup.monitor.stoppedIdentifiers.contains("g1"))
        #expect(setup.monitor.startedRegions.last { $0.identifier == "g1" }?.radius == 250)
    }

    @Test
    func handleMovement_givenEmptyAreaLoop_expectTriggerWalksWithoutChurn() async {
        // The geofence-free corridor: empty response, empty cache, trigger armed. Every 5 km refetch
        // comes back empty again — the trigger must keep walking forward without a stop-all cycle.
        let setup = await makeRegisteredSetup(regions: [], config: diffConfig, storage: makeStorage())

        let newLocation = LocationData(latitude: 0, longitude: 0.05)
        let result = await setup.coordinator.handleMovement(latitude: newLocation.latitude, longitude: newLocation.longitude)

        #expect(result.isSuccess)
        #expect(setup.api.fetchNearbyGeofencesCallsCount == 2)
        #expect(setup.monitor.stopAllCallCount == 0)
        let triggerStarts = setup.monitor.startedRegions.filter { $0.identifier == GeofenceConstants.movementTriggerIdentifier }
        #expect(triggerStarts.count == 2)
        #expect(triggerStarts.last?.center == newLocation)
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
        api.fetchNearbyGeofencesClosure = { _, _, completion in
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
        api.fetchNearbyGeofencesClosure = { _, _, completion in
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
        api.fetchNearbyGeofencesClosure = { _, _, completion in
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
        api.fetchNearbyGeofencesClosure = { _, _, completion in
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
        api.fetchNearbyGeofencesClosure = { _, _, completion in
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

    // MARK: - Oversized covering circles

    /// Both monitors clamp a radius to the OS limit. For a circle that is graceful — the monitored
    /// circle IS the fence, so a smaller one just reports later. For a polygon it is not: a clamped
    /// circle no longer contains the polygon, so the covering-circle exit stops being geometric
    /// certainty and becomes a false exit. Such a polygon is dropped instead, while the circle
    /// alongside it still registers — the control that proves the drop is selective.
    @Test
    func remoteRefresh_givenPolygonCoveringCircleOverOsLimit_expectDroppedButCircleRegistered() async {
        let anchor = LocationData(latitude: 0, longitude: 0)
        let storage = makeStorage()
        let dateUtil = DateUtilStub()
        await storage.recordSync(timestamp: dateUtil.givenNow.addingTimeInterval(-25 * 60 * 60), location: LocationData(latitude: 0, longitude: 0))
        let oversizedPolygon = Geofence(
            id: "poly", latitude: 0, longitude: 0, radius: 5000, name: nil,
            transitionTypes: [.enter, .exit], lastUpdated: dateUtil.givenNow,
            vertices: [
                LocationData(latitude: -0.01, longitude: -0.01),
                LocationData(latitude: -0.01, longitude: 0.01),
                LocationData(latitude: 0.01, longitude: 0.01),
                LocationData(latitude: 0.01, longitude: -0.01)
            ]
        )
        let oversizedCircle = Geofence(
            id: "circle", latitude: 0, longitude: 0, radius: 5000, name: nil,
            transitionTypes: [.enter, .exit], lastUpdated: dateUtil.givenNow
        )
        let api = GeofenceApiServiceMock()
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            completion(.success(makeApiResponse(regions: [oversizedPolygon, oversizedCircle])))
        }
        let monitor = MockGeofenceRegionMonitor()
        monitor.maximumMonitoringRadius = 1000
        let setup = makeCoordinator(api: api, storage: storage, monitor: monitor, dateUtil: dateUtil)

        _ = await setup.coordinator.refresh(latitude: anchor.latitude, longitude: anchor.longitude)

        let registered = Set(setup.monitor.startedRegions.map(\.identifier))
        #expect(!registered.contains("poly"))
        #expect(registered.contains("circle"))
    }

    /// A polygon the OS will refuse must not consume one of `maxBusinessGeofences`: dropping it
    /// after ranking left the slot empty even with a usable candidate waiting behind it.
    @Test
    func remoteRefresh_givenOversizedPolygonAndSpareCandidate_expectSlotGoesToTheNextRegion() async {
        let anchor = LocationData(latitude: 0, longitude: 0)
        let storage = makeStorage()
        let dateUtil = DateUtilStub()
        await storage.recordSync(timestamp: dateUtil.givenNow.addingTimeInterval(-25 * 60 * 60), location: anchor)
        let oversizedPolygon = Geofence(
            id: "poly", latitude: 0, longitude: 0, radius: 5000, name: nil,
            transitionTypes: [.enter, .exit], lastUpdated: dateUtil.givenNow,
            vertices: [
                LocationData(latitude: -0.01, longitude: -0.01),
                LocationData(latitude: -0.01, longitude: 0.01),
                LocationData(latitude: 0.01, longitude: 0.01),
                LocationData(latitude: 0.01, longitude: -0.01)
            ]
        )
        // Nearer than the spare, so ranking puts it in the single available slot.
        let spare = Geofence(
            id: "spare", latitude: 0.02, longitude: 0.02, radius: 100, name: nil,
            transitionTypes: [.enter, .exit], lastUpdated: dateUtil.givenNow
        )
        let config = GeofenceConfig(
            localRefreshTriggerRadius: 750, remoteFetchRefreshTriggerRadius: 3000,
            remoteFetchRefreshExpiry: 86400, duplicateEventsExpiry: 60,
            maxBusinessGeofences: 1, maxMonitoringDistance: 100000
        )
        let api = GeofenceApiServiceMock()
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            completion(.success(makeApiResponse(regions: [oversizedPolygon, spare], config: config)))
        }
        let monitor = MockGeofenceRegionMonitor()
        monitor.maximumMonitoringRadius = 1000
        let setup = makeCoordinator(api: api, storage: storage, monitor: monitor, dateUtil: dateUtil)

        _ = await setup.coordinator.refresh(latitude: anchor.latitude, longitude: anchor.longitude)

        #expect(setup.monitor.startedRegions.map(\.identifier).contains("spare"))
    }

    /// A polygon's covering circle is machinery: it must report both edges regardless of the
    /// customer's transition types, or the resolver never sees the edge it needs to advance belief.
    @Test
    func remoteRefresh_givenEnterOnlyPolygon_expectCoveringCircleRegisteredWithBothEdges() async {
        let anchor = LocationData(latitude: 0, longitude: 0)
        let storage = makeStorage()
        let dateUtil = DateUtilStub()
        await storage.recordSync(timestamp: dateUtil.givenNow.addingTimeInterval(-25 * 60 * 60), location: anchor)
        let enterOnly = Geofence(
            id: "poly", latitude: 0, longitude: 0, radius: 300, name: nil,
            transitionTypes: [.enter], lastUpdated: dateUtil.givenNow,
            vertices: [
                LocationData(latitude: -0.001, longitude: -0.001),
                LocationData(latitude: -0.001, longitude: 0.001),
                LocationData(latitude: 0.001, longitude: 0.001),
                LocationData(latitude: 0.001, longitude: -0.001)
            ]
        )
        let enterOnlyCircle = Geofence(
            id: "circle", latitude: 0, longitude: 0, radius: 120, name: nil,
            transitionTypes: [.enter], lastUpdated: dateUtil.givenNow
        )
        let api = GeofenceApiServiceMock()
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            completion(.success(makeApiResponse(regions: [enterOnly, enterOnlyCircle])))
        }
        let setup = makeCoordinator(api: api, storage: storage, dateUtil: dateUtil)

        _ = await setup.coordinator.refresh(latitude: anchor.latitude, longitude: anchor.longitude)

        let polygonRequest = setup.monitor.startedRegions.first { $0.identifier == "poly" }
        #expect(polygonRequest?.transitionTypes == [.enter, .exit])
        // A real circle keeps the customer's types — the change is polygon-only.
        let circleRequest = setup.monitor.startedRegions.first { $0.identifier == "circle" }
        #expect(circleRequest?.transitionTypes == [.enter])
    }

    /// The dropped polygon must not be recorded as registered either: `evaluateAllPolygons` reads
    /// that set, so recording it would have the resolver decide membership for a fence the OS never
    /// took — an enter with no wake behind it and no exit to balance it.
    @Test
    func remoteRefresh_givenPolygonCoveringCircleOverOsLimit_expectNotRecordedAsRegistered() async {
        let anchor = LocationData(latitude: 0, longitude: 0)
        let storage = makeStorage()
        let dateUtil = DateUtilStub()
        await storage.recordSync(timestamp: dateUtil.givenNow.addingTimeInterval(-25 * 60 * 60), location: anchor)
        let oversizedPolygon = Geofence(
            id: "poly", latitude: 0, longitude: 0, radius: 5000, name: nil,
            transitionTypes: [.enter, .exit], lastUpdated: dateUtil.givenNow,
            vertices: [
                LocationData(latitude: -0.01, longitude: -0.01),
                LocationData(latitude: -0.01, longitude: 0.01),
                LocationData(latitude: 0.01, longitude: 0.01),
                LocationData(latitude: 0.01, longitude: -0.01)
            ]
        )
        let smallCircle = Geofence(
            id: "circle", latitude: 0, longitude: 0, radius: 100, name: nil,
            transitionTypes: [.enter, .exit], lastUpdated: dateUtil.givenNow
        )
        let api = GeofenceApiServiceMock()
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            completion(.success(makeApiResponse(regions: [oversizedPolygon, smallCircle])))
        }
        let monitor = MockGeofenceRegionMonitor()
        monitor.maximumMonitoringRadius = 1000
        let setup = makeCoordinator(api: api, storage: storage, monitor: monitor, dateUtil: dateUtil)

        _ = await setup.coordinator.refresh(latitude: anchor.latitude, longitude: anchor.longitude)

        let recorded = await storage.getRegisteredBusinessIds()
        #expect(!recorded.contains("poly"))
        #expect(recorded.contains("circle"))
    }

    // MARK: - Initial enter-when-inside (diff-based, both monitor paths)

    /// A polygon's `radius` is its covering circle, so the containment test that serves circles
    /// would emit an enter for a device sitting in the annulus — a crossing that never happened.
    /// Polygons are excluded here and decided by the resolver's gated evaluation instead.
    ///
    /// The circle in the same pass is the negative control: it proves the harness would have caught
    /// an emit, so the polygon's silence is the exclusion working and not a dead assertion.
    @Test
    func remoteRefresh_givenNewPolygonCoveringAnchorButNotContainingIt_expectNoInitialEnter() async {
        let anchor = LocationData(latitude: 0, longitude: 0)
        // Square sitting ~111 m north of the anchor: every vertex is inside the 400 m covering
        // circle, while the anchor itself is outside the polygon.
        let polygon = Geofence(
            id: "poly", latitude: 0, longitude: 0, radius: 400, name: nil,
            transitionTypes: [.enter, .exit], lastUpdated: Date(),
            vertices: [
                LocationData(latitude: 0.001, longitude: -0.0016),
                LocationData(latitude: 0.001, longitude: 0.0016),
                LocationData(latitude: 0.0026, longitude: 0.0016),
                LocationData(latitude: 0.0026, longitude: -0.0016)
            ]
        )
        let circle = Geofence(
            id: "circle", latitude: 0, longitude: 0, radius: 400, name: nil,
            transitionTypes: [.enter, .exit], lastUpdated: Date()
        )

        let emitter = await runRemoteRefresh(regions: [polygon, circle], anchor: anchor, previousIds: [])
        await awaitEmits(emitter, count: 1)

        let emitted = emitter.calls.wrappedValue
        #expect(emitted.count == 1)
        #expect(emitted.first?.geofenceId == "circle")
    }

    /// Drives a remote refresh that fetches `regions`, anchored at `anchor`, with `previousIds`
    /// already recorded as registered. The emit is fire-and-forget, so callers poll via `awaitEmits`.
    private func runRemoteRefresh(regions: [Geofence], anchor: LocationData, previousIds: Set<String>) async -> TransitionEmitterSpy {
        let storage = makeStorage()
        // Stale sync so the freshness gate routes to a remote fetch.
        let dateUtil = DateUtilStub()
        await storage.recordSync(timestamp: dateUtil.givenNow.addingTimeInterval(-25 * 60 * 60), location: LocationData(latitude: 0, longitude: 0))
        if !previousIds.isEmpty {
            await storage.recordRegistration(center: anchor, businessIds: previousIds)
        }
        let api = GeofenceApiServiceMock()
        api.fetchNearbyGeofencesClosure = { _, _, completion in completion(.success(makeApiResponse(regions: regions))) }
        let setup = makeCoordinator(api: api, storage: storage, dateUtil: dateUtil)
        _ = await setup.coordinator.refresh(latitude: anchor.latitude, longitude: anchor.longitude)
        return setup.emitter
    }

    /// Polls the fire-and-forget emit Task until it has recorded `count` calls, then yields a few more
    /// times so any unwanted extra emit would surface before the caller asserts an exact set.
    private func awaitEmits(_ emitter: TransitionEmitterSpy, count: Int) async {
        for _ in 0 ..< 100 where emitter.calls.wrappedValue.count < count {
            await Task.yield()
        }
        for _ in 0 ..< 5 {
            await Task.yield()
        }
    }

    @Test
    func refresh_givenNewGeofenceDeviceInside_expectInitialEnterEmitted() async {
        let anchor = LocationData(latitude: 1.0, longitude: 2.0)
        // Region centered on the anchor → device is inside; no prior registration → genuinely new.
        let emitter = await runRemoteRefresh(regions: [makeRegion(id: "g1", latitude: 1.0, longitude: 2.0)], anchor: anchor, previousIds: [])
        await awaitEmits(emitter, count: 1)
        #expect(emitter.calls.wrappedValue.map(\.geofenceId) == ["g1"])
        #expect(emitter.calls.wrappedValue.first?.transition == .enter)
    }

    @Test
    func refresh_givenMixOfNewGeofences_expectOnlyContainingEnterTypeEmitted() async {
        let anchor = LocationData(latitude: 1.0, longitude: 2.0)
        // inside+enter g1 → emitted; ~222m-away g2 → registered but outside; inside exit-only g3.
        // Awaiting g1 proves the emit loop ran, so g2/g3 are conclusively excluded (non-vacuous).
        let g2 = makeRegion(id: "g2", latitude: 1.002, longitude: 2.0)
        let g3 = Geofence(id: "g3", latitude: 1.0, longitude: 2.0, radius: 100, name: "g3", transitionTypes: [.exit], lastUpdated: Date(timeIntervalSince1970: 1700000000))
        let emitter = await runRemoteRefresh(regions: [makeRegion(id: "g1", latitude: 1.0, longitude: 2.0), g2, g3], anchor: anchor, previousIds: [])
        await awaitEmits(emitter, count: 1)
        #expect(emitter.calls.wrappedValue.map(\.geofenceId) == ["g1"])
    }

    @Test
    func refresh_givenNewAndAlreadyRegisteredInside_expectOnlyNewEmitted() async {
        let anchor = LocationData(latitude: 1.0, longitude: 2.0)
        // Both inside; gOld is already registered (a wholesale re-registration) → excluded by the diff;
        // gNew is genuinely new → emitted. Emitting only gNew proves the diff, non-vacuously.
        let regions = [makeRegion(id: "gOld", latitude: 1.0, longitude: 2.0), makeRegion(id: "gNew", latitude: 1.0, longitude: 2.0)]
        let emitter = await runRemoteRefresh(regions: regions, anchor: anchor, previousIds: ["gOld"])
        await awaitEmits(emitter, count: 1)
        #expect(emitter.calls.wrappedValue.map(\.geofenceId) == ["gNew"])
    }

    @Test
    func localRefresh_givenNewGeofenceInside_expectInitialEnterEmitted() async {
        // Cover the LOCAL refresh call site: recent sync (not time-stale) + cached region but no
        // recorded registration → refreshAction routes to a local re-rank, not a fetch.
        let anchor = LocationData(latitude: 1.0, longitude: 2.0)
        let storage = makeStorage()
        let dateUtil = DateUtilStub()
        await storage.setCachedGeofences([makeRegion(id: "g1", latitude: 1.0, longitude: 2.0)])
        await storage.setCachedConfig(.fallback)
        await storage.recordSync(timestamp: dateUtil.givenNow.addingTimeInterval(-60), location: anchor)
        let setup = makeCoordinator(storage: storage, dateUtil: dateUtil)

        _ = await setup.coordinator.refresh(latitude: anchor.latitude, longitude: anchor.longitude)

        await awaitEmits(setup.emitter, count: 1)
        #expect(setup.api.fetchNearbyGeofencesCallsCount == 0) // local path — no fetch
        #expect(setup.emitter.calls.wrappedValue.map(\.geofenceId) == ["g1"])
    }

    @Test
    func refresh_givenNewGeofenceInsideButRegistrationRejected_expectNoInitialEnter() async {
        // The device is inside a genuinely-new fence, but the monitor drops it (blocked permission /
        // invalid coordinates), so it isn't monitored — no synthetic enter it could never balance.
        let anchor = LocationData(latitude: 1.0, longitude: 2.0)
        let storage = makeStorage()
        let dateUtil = DateUtilStub()
        await storage.recordSync(timestamp: dateUtil.givenNow.addingTimeInterval(-25 * 60 * 60), location: LocationData(latitude: 0, longitude: 0))
        let api = GeofenceApiServiceMock()
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            completion(.success(makeApiResponse(regions: [makeRegion(id: "g1", latitude: 1.0, longitude: 2.0)])))
        }
        let monitor = MockGeofenceRegionMonitor()
        monitor.rejectedIdentifiers = ["g1"]
        let setup = makeCoordinator(api: api, storage: storage, monitor: monitor, dateUtil: dateUtil)

        _ = await setup.coordinator.refresh(latitude: anchor.latitude, longitude: anchor.longitude)

        // No count to await — assert nothing emitted after yielding the fire-and-forget window. The
        // sibling "device inside" test proves this same setup DOES emit without the rejection, so
        // this is non-vacuous.
        await awaitEmits(setup.emitter, count: 0)
        #expect(setup.emitter.calls.wrappedValue.isEmpty)
    }

    @Test
    func handleMovement_givenRegisteredRegionReshapedThenRejected_expectNoLongerReportedRegistered() async {
        // A region already registered gets reshaped, and the monitor now rejects it (permission
        // revoked, or the backend moved it to invalid coordinates). The stale claim must go with
        // the failed re-registration — otherwise it keeps counting toward the registered set and
        // `emitInitialEnters` can fire an enter for a region the OS is not monitoring.
        let storage = makeStorage()
        let dateUtil = DateUtilStub()
        await storage.setCachedConfig(diffConfig)
        await storage.recordSync(timestamp: dateUtil.givenNow.addingTimeInterval(-100), location: LocationData(latitude: 0, longitude: 0))
        await storage.setCachedGeofences([makeRegion(id: "g1", latitude: 0.001, longitude: 0, radius: 500)])
        let setup = makeCoordinator(storage: storage, dateUtil: dateUtil)

        _ = await setup.coordinator.refresh(latitude: 0, longitude: 0)
        #expect(setup.monitor.monitoredRegionIdentifiers.contains("g1"))

        // Same id, different circle, and the monitor now refuses it.
        await storage.setCachedGeofences([makeRegion(id: "g1", latitude: 0.001, longitude: 0, radius: 900)])
        setup.monitor.rejectedIdentifiers = ["g1"]
        _ = await setup.coordinator.handleMovement(latitude: 0, longitude: 0.001)

        #expect(!setup.monitor.monitoredRegionIdentifiers.contains("g1"))
        // And the circle it held before the refused reshape is gone from the OS, not left occupying
        // one of the 20 slots with nothing owning it and no later pass repairing it.
        #expect(!setup.monitor.osMonitoredRegions.contains("g1"))
        #expect(setup.monitor.osGeometry(for: "g1") == nil)
    }

    @Test
    func refresh_givenDeviceInsideConfiguredRadiusButOutsideOsCap_expectNoInitialEnter() async {
        // The fence's configured radius exceeds the OS cap, so the monitor registers a smaller clamped
        // circle. The device is inside the configured radius but outside the clamped one, so the inside
        // check (which clamps to the same cap) must not emit a synthetic enter.
        let anchor = LocationData(latitude: 1.0, longitude: 2.0)
        let storage = makeStorage()
        let dateUtil = DateUtilStub()
        await storage.recordSync(timestamp: dateUtil.givenNow.addingTimeInterval(-25 * 60 * 60), location: LocationData(latitude: 0, longitude: 0))
        let api = GeofenceApiServiceMock()
        // Center ~5 km from the anchor with a 100 km configured radius (device inside configured
        // circle); the monitor clamps monitoring to 200 m, which the device is well outside.
        let region = makeRegion(id: "g1", latitude: 1.045, longitude: 2.0, radius: 100000)
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            completion(.success(makeApiResponse(regions: [region])))
        }
        let monitor = MockGeofenceRegionMonitor()
        monitor.maximumMonitoringRadius = 200
        let setup = makeCoordinator(api: api, storage: storage, monitor: monitor, dateUtil: dateUtil)

        _ = await setup.coordinator.refresh(latitude: anchor.latitude, longitude: anchor.longitude)

        await awaitEmits(setup.emitter, count: 0)
        #expect(setup.emitter.calls.wrappedValue.isEmpty)
    }

    @Test
    func refresh_givenUserChangesMidInitialEnterBatch_expectRemainingSuppressed() async {
        // Two new-inside fences. The identity changes while the first enter is being delivered; the
        // per-iteration guard must stop the batch so the second isn't stamped to the new user.
        let anchor = LocationData(latitude: 1.0, longitude: 2.0)
        let storage = makeStorage()
        let dateUtil = DateUtilStub()
        await storage.recordSync(timestamp: dateUtil.givenNow.addingTimeInterval(-25 * 60 * 60), location: LocationData(latitude: 0, longitude: 0))
        let api = GeofenceApiServiceMock()
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            completion(.success(makeApiResponse(regions: [
                makeRegion(id: "g1", latitude: 1.0, longitude: 2.0),
                makeRegion(id: "g2", latitude: 1.0, longitude: 2.0)
            ])))
        }
        let contextStore = makeContextStore(userId: "user-1")
        let emitter = TransitionEmitterSpy()
        emitter.onEmit = { index in if index == 0 { contextStore.setUserId("user-2") } }
        let setup = makeCoordinator(api: api, storage: storage, contextStore: contextStore, emitter: emitter, dateUtil: dateUtil)

        _ = await setup.coordinator.refresh(latitude: anchor.latitude, longitude: anchor.longitude)

        // Exactly one delivered: the guard stopped the batch after the first send changed identity.
        // Without the per-iteration recheck, both would fire (count == 2).
        await awaitEmits(emitter, count: 1)
        #expect(emitter.calls.wrappedValue.count == 1)
    }

    @Test
    func refresh_givenSignOutDuringRegisterPersist_expectStaleStateUndone() async {
        // Sign-out lands AFTER the post-fetch user check, during the register/persist window — where
        // reset() would be dropped on the held gate. The refresh must undo its own stale-user state.
        let contextStore = makeContextStore(userId: "user-1")
        let backing = makeStorage()
        let dateUtil = DateUtilStub()
        await backing.recordSync(timestamp: dateUtil.givenNow.addingTimeInterval(-25 * 60 * 60), location: LocationData(latitude: 0, longitude: 0))
        // Flip to signed-out on the first storage write after the post-fetch check.
        let spy = SpyGeofenceSyncStorage(underlying: backing, onSetCachedGeofences: { contextStore.setUserId(nil) })
        let api = GeofenceApiServiceMock()
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            completion(.success(makeApiResponse(regions: [makeRegion(id: "g1", latitude: 0, longitude: 0)])))
        }
        let setup = makeCoordinator(api: api, storage: spy, contextStore: contextStore, dateUtil: dateUtil)

        let result = await setup.coordinator.refresh(latitude: 0, longitude: 0)

        #expect(result.isSuccess)
        // Cleanup ran: monitoring torn down wholesale, user-scoped state cleared, and no initial
        // enters for the signed-out user.
        #expect(setup.monitor.stopAllCallCount == 1)
        #expect(setup.monitor.monitoredRegionIdentifiers.isEmpty)
        #expect(await backing.getRegisteredBusinessIds().isEmpty)
        #expect(await backing.getLastSync() == nil)
        #expect(setup.emitter.calls.wrappedValue.isEmpty)
    }

    @Test
    func refresh_givenSignOutBeforeFetchFailure_expectStaleStateUndone() async {
        // Sign-out lands during the fetch and the fetch then fails — an early exit that used to
        // return before any cleanup, leaving the previous user's registrations and sync anchors
        // behind (their reset() was dropped on the held gate).
        let contextStore = makeContextStore(userId: "user-1")
        let storage = makeStorage()
        await storage.recordSync(timestamp: Date(timeIntervalSince1970: 1), location: LocationData(latitude: 0, longitude: 0))
        await storage.recordRegistration(center: LocationData(latitude: 0, longitude: 0), businessIds: ["g1"])
        let api = GeofenceApiServiceMock()
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            contextStore.setUserId(nil)
            completion(.failure(.transport))
        }
        let setup = makeCoordinator(api: api, storage: storage, contextStore: contextStore)

        let result = await setup.coordinator.refresh(latitude: 0, longitude: 0)

        #expect(result.errorOrNil == .fetchFailed(.transport))
        // The exit cleanup ran: monitoring stopped and the stale user-scoped state cleared.
        #expect(setup.monitor.stopAllCallCount == 1)
        #expect(await storage.getRegisteredBusinessIds().isEmpty)
        #expect(await storage.getLastSync() == nil)
    }

    @Test
    func refresh_givenSignOutDuringFreshnessSkip_expectStaleStateUndone() async {
        // Sign-out lands while a refresh is deciding it has fresh data ("skip") — the shortest
        // gated path, with no register/persist at all. The dropped reset()'s cleanup must still
        // run before the gate is released.
        let contextStore = makeContextStore(userId: "user-1")
        let backing = makeStorage()
        let dateUtil = DateUtilStub()
        await backing.recordSync(timestamp: dateUtil.givenNow.addingTimeInterval(-100), location: LocationData(latitude: 0, longitude: 0))
        await backing.recordRegistration(center: LocationData(latitude: 0, longitude: 0), businessIds: ["g1"])
        let spy = SpyGeofenceSyncStorage(underlying: backing, onGetLastSync: { contextStore.setUserId(nil) })
        let setup = makeCoordinator(storage: spy, contextStore: contextStore, dateUtil: dateUtil)

        let result = await setup.coordinator.refresh(latitude: 0, longitude: 0)

        #expect(result.isSuccess)
        #expect(setup.api.fetchNearbyGeofencesCallsCount == 0)
        #expect(setup.monitor.stopAllCallCount == 1)
        #expect(await backing.getRegisteredBusinessIds().isEmpty)
        #expect(await backing.getLastSync() == nil)
    }

    @Test
    func reset_givenDroppedDuringInFlightRefresh_expectCleanupBeforeGateRelease() async {
        // The reviewer's end-to-end scenario: reset() fires while a refresh holds the gate and is
        // dropped as .alreadyInProgress; the refresh (here failing its fetch) must run the
        // sign-out's cleanup before releasing the gate.
        let contextStore = makeContextStore(userId: "user-1")
        let storage = makeStorage()
        await storage.recordRegistration(center: LocationData(latitude: 0, longitude: 0), businessIds: ["g1"])
        let api = GeofenceApiServiceMock()
        let heldCompletion = CompletionBox()
        let (fetchStarted, fetchStartedContinuation) = AsyncStream<Void>.makeStream()
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            heldCompletion.completion = completion
            fetchStartedContinuation.yield()
        }
        let setup = makeCoordinator(api: api, storage: storage, contextStore: contextStore)

        let refreshTask = Task { await setup.coordinator.refresh(latitude: 0, longitude: 0) }
        for await _ in fetchStarted {
            break
        }
        // Refresh is suspended in the fetch, holding the gate. Sign out and fire the reset.
        contextStore.setUserId(nil)
        let resetResult = await setup.coordinator.reset()
        #expect(resetResult.errorOrNil == .alreadyInProgress)
        // Reset was dropped — nothing cleaned yet.
        #expect(setup.monitor.stopAllCallCount == 0)

        heldCompletion.completion?(.failure(.transport))
        let refreshResult = await refreshTask.value

        #expect(refreshResult.errorOrNil == .fetchFailed(.transport))
        #expect(setup.monitor.stopAllCallCount == 1)
        #expect(await storage.getRegisteredBusinessIds().isEmpty)
        // Signed out (nobody current) → no self-heal retry, so no second fetch.
        #expect(setup.api.fetchNearbyGeofencesCallsCount == 1)
    }

    @Test
    func refresh_givenUserSwitchMidFetch_expectSelfHealRegistersNewUser() async {
        // A signs out and B signs in while A's refresh is in flight: B's own refresh would be
        // dropped on the held gate, and the exit cleanup stops everything — leaving the device
        // unmonitored. The self-heal retry must re-run for B so the switch converges to a
        // registered state instead of an outage until the next launch.
        let contextStore = makeContextStore(userId: "user-1")
        let storage = makeStorage()
        let api = GeofenceApiServiceMock()
        let fetchCount = Synchronized<Int>(0)
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            let call = fetchCount.mutating { count -> Int in
                count += 1
                return count
            }
            // First fetch belongs to user-1; flip to user-2 mid-flight so the post-fetch check
            // supersedes it and the exit cleanup + retry run.
            if call == 1 { contextStore.setUserId("user-2") }
            completion(.success(makeApiResponse(regions: [makeRegion(id: "g1", latitude: 0, longitude: 0)])))
        }
        let setup = makeCoordinator(api: api, storage: storage, contextStore: contextStore)

        let result = await setup.coordinator.refresh(latitude: 0, longitude: 0)
        #expect(result.isSuccess)

        // The retry is fire-and-forget; wait for its registration to land.
        for _ in 0 ..< 1000 {
            let registered = await storage.getRegisteredBusinessIds()
            if !registered.isEmpty { break }
            await Task.yield()
        }
        #expect(fetchCount.wrappedValue == 2)
        #expect(await storage.getRegisteredBusinessIds() == ["g1"])
        #expect(setup.monitor.startedRegions.contains { $0.identifier == "g1" })
    }
}

/// Holds a fetch completion across concurrency domains so a test can resolve it after
/// choreographing concurrent calls. `@unchecked Sendable`: writes and reads are sequenced by the
/// fetch-started signal.
private final class CompletionBox: @unchecked Sendable {
    var completion: ((Result<GeofenceApiResponse, GeofenceApiError>) -> Void)?
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
    /// Runs at the start of `setCachedGeofences` — the first storage write after the post-fetch user
    /// check — so a test can flip the identified user inside the register/persist window.
    private let onSetCachedGeofences: (@Sendable () -> Void)?
    /// Runs at the start of `getLastSync` — inside the freshness decision — so a test can flip the
    /// identified user on a refresh that will exit via the skip path.
    private let onGetLastSync: (@Sendable () -> Void)?

    init(
        underlying: GeofenceStorage,
        onSetCachedGeofences: (@Sendable () -> Void)? = nil,
        onGetLastSync: (@Sendable () -> Void)? = nil
    ) {
        self.underlying = underlying
        self.onSetCachedGeofences = onSetCachedGeofences
        self.onGetLastSync = onGetLastSync
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
        onGetLastSync?()
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
        onSetCachedGeofences?()
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

// MARK: - Transition emitter spy

/// Records the synthetic transitions the coordinator fires for initial enter-when-inside.
private final class TransitionEmitterSpy: GeofenceTransitionEmitting, @unchecked Sendable {
    let calls = Synchronized<[(geofenceId: String, transition: GeofenceTransition)]>([])
    /// Invoked after each recorded emit with its 0-based index — lets a test mutate state mid-batch
    /// (e.g. change the identified user) to exercise the per-iteration guard.
    var onEmit: (@Sendable (Int) -> Void)?

    func trackTransition(geofenceId: String, transition: GeofenceTransition) async {
        let index = calls.mutating { calls -> Int in
            calls.append((geofenceId, transition))
            return calls.count - 1
        }
        onEmit?(index)
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
