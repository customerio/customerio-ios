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
                carriesPolygonFields: region.vertices != nil,
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

        let result = await setup.coordinator.refresh(latitude: 1.0, longitude: 2.0, anchorIsLiveFix: true)

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
        let result = await setup.coordinator.refresh(latitude: 0, longitude: 0, anchorIsLiveFix: true)

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
        let result = await setup.coordinator.refresh(latitude: 0.02, longitude: 0, anchorIsLiveFix: true)

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
        let result = await setup.coordinator.refresh(latitude: 0, longitude: 0, anchorIsLiveFix: true)

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

        let result = await setup.coordinator.refresh(latitude: 0, longitude: 0, anchorIsLiveFix: true)

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

        let result = await setup.coordinator.refresh(latitude: 0, longitude: 0, anchorIsLiveFix: true)

        #expect(result.isSuccess)
        #expect(api.fetchNearbyGeofencesCallsCount == 1)
    }

    /// A non-live anchor is not "an old fix near here" — `bestKnownFix` applies no age gate, so it
    /// can be an OS cache value hours old and kilometres away. Ranking and re-planting around one
    /// drops the fences that are actually nearby and leaves a movement trigger the device is not
    /// inside; on the classic path that trigger never fires again.
    ///
    /// Anchoring on the registration centre instead keeps a time-expired catalog refetchable while
    /// making distance-driven work impossible from a point we cannot trust.
    @Test
    func refresh_givenANonLiveAnchorFarFromTheRegistrationCentre_expectItDoesNotMoveAnything() async {
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
        // Fresh in time and registered here, so distance is the only thing that could do work.
        await storage.recordSync(timestamp: dateUtil.givenNow, location: LocationData(latitude: 0, longitude: 0))
        await storage.recordRegistration(center: LocationData(latitude: 0, longitude: 0), businessIds: ["g1"])
        let api = GeofenceApiServiceMock()
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            completion(.success(makeApiResponse(regions: [])))
        }
        let setup = makeCoordinator(api: api, storage: storage, dateUtil: dateUtil)

        // ~157 km away: on the raw anchor this is far past the refetch radius.
        let result = await setup.coordinator.refresh(latitude: 1.0, longitude: 1.0, anchorIsLiveFix: false)

        #expect(result.isSuccess)
        #expect(api.fetchNearbyGeofencesCallsCount == 0)
        #expect(await storage.getLastRegistrationCenter() == LocationData(latitude: 0, longitude: 0))
    }

    /// The other direction, so the guard above cannot degrade into "a refresh never moves anything":
    /// a caller that really did obtain a fix for this event still re-ranks around it.
    @Test
    func refresh_givenALiveAnchorFarFromTheRegistrationCentre_expectItStillRefetches() async {
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
        await storage.recordSync(timestamp: dateUtil.givenNow, location: LocationData(latitude: 0, longitude: 0))
        await storage.recordRegistration(center: LocationData(latitude: 0, longitude: 0), businessIds: ["g1"])
        let api = GeofenceApiServiceMock()
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            completion(.success(makeApiResponse(regions: [])))
        }
        let setup = makeCoordinator(api: api, storage: storage, dateUtil: dateUtil)

        let result = await setup.coordinator.refresh(latitude: 1.0, longitude: 1.0, anchorIsLiveFix: true)

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
        let result = await setup.coordinator.refresh(latitude: 1.0, longitude: 2.0, anchorIsLiveFix: true)

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
        let result = await setup.coordinator.refresh(latitude: 0, longitude: 0, anchorIsLiveFix: true)

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

        let result = await setup.coordinator.refresh(latitude: 1.0, longitude: 2.0, anchorIsLiveFix: true)

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

        let result = await setup.coordinator.refresh(latitude: 1.0, longitude: 2.0, anchorIsLiveFix: true)

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
        let result = await setup.coordinator.refresh(latitude: 1.0, longitude: 2.0, anchorIsLiveFix: true)

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
        _ = await setup.coordinator.refresh(latitude: 1.0, longitude: 2.0, anchorIsLiveFix: true)

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
        _ = await setup.coordinator.refresh(latitude: 1.0, longitude: 2.0, anchorIsLiveFix: true)

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
        _ = await setup.coordinator.refresh(latitude: 0, longitude: 0, anchorIsLiveFix: true)

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
        _ = await setup.coordinator.refresh(latitude: 37.7749, longitude: -122.4194, anchorIsLiveFix: true)

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
            geometry: nil, enclosingCircle: nil, carriesPolygonFields: false, externalId: nil,
            transitionTypes: nil, lastUpdated: nil, geosetIds: nil, metadata: nil
        )
        let api = GeofenceApiServiceMock()
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            completion(.success(GeofenceApiResponse(config: nil, geofences: [unusable])))
        }

        let setup = makeCoordinator(api: api, storage: storage)
        let result = await setup.coordinator.refresh(latitude: 37.7749, longitude: -122.4194, anchorIsLiveFix: true)

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
        let result = await setup.coordinator.refresh(latitude: 37.7749, longitude: -122.4194, anchorIsLiveFix: true)

        #expect(result.errorOrNil == .fetchFailed(.decoding))
        #expect(await storage.getCachedGeofences().map(\.id) == ["kept"])
    }

    /// Polygon fields with no shape discriminator is a MALFORMED payload, not a workspace that has
    /// moved to a shape we cannot monitor — so it must preserve the cache, the way a decode loss
    /// does. Both used to report `unknownShape`, which the all-dropped guard exempts, so this
    /// payload cleared every fence the user had. Reproduction supplied by @Shahroz16 in review.
    @Test
    func refresh_givenPolygonFieldsWithoutShape_expectFetchFailureAndCacheKept() async throws {
        let storage = makeStorage()
        await storage.setCachedGeofences([makeRegion(id: "kept", latitude: 37.7749, longitude: -122.4194)])
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload = #"{"geofences":[{"id":"broken","latitude":1,"longitude":2,"radius":100,"geometry":{}}]}"#
        let response = try decoder.decode(GeofenceApiResponse.self, from: Data(payload.utf8))
        let api = GeofenceApiServiceMock()
        api.fetchNearbyGeofencesClosure = { _, _, completion in completion(.success(response)) }

        let setup = makeCoordinator(api: api, storage: storage)
        let result = await setup.coordinator.refresh(latitude: 37.7749, longitude: -122.4194, anchorIsLiveFix: true)

        #expect(result.errorOrNil == .fetchFailed(.decoding))
        #expect(await storage.getCachedGeofences().map(\.id) == ["kept"])
        #expect(setup.monitor.startedRegions.isEmpty)
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
            geometry: nil, enclosingCircle: nil, carriesPolygonFields: false, externalId: nil,
            transitionTypes: nil, lastUpdated: nil, geosetIds: nil, metadata: nil
        )
        let api = GeofenceApiServiceMock()
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            completion(.success(GeofenceApiResponse(config: nil, geofences: [futureShape])))
        }

        let setup = makeCoordinator(api: api, storage: storage)
        let result = await setup.coordinator.refresh(latitude: 37.7749, longitude: -122.4194, anchorIsLiveFix: true)

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
        _ = await setup.coordinator.refresh(latitude: 37.7749, longitude: -122.4194, anchorIsLiveFix: true)

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
        _ = await setup.coordinator.refresh(latitude: 37.7749, longitude: -122.4194, anchorIsLiveFix: true)

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
        _ = await setup.coordinator.refresh(latitude: 1.0, longitude: 2.0, anchorIsLiveFix: true)

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
        async let first = setup.coordinator.refresh(latitude: 1.0, longitude: 2.0, anchorIsLiveFix: true)
        // Wait for the first call to enter the API mock before firing the second, so the
        // dedup-gate test is deterministic instead of timing-dependent.
        await firstReachedApi.wait()
        let second = await setup.coordinator.refresh(latitude: 3.0, longitude: 4.0, anchorIsLiveFix: true)
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

        _ = await setup.coordinator.refresh(latitude: 1.0, longitude: 2.0, anchorIsLiveFix: true)

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

        _ = await setup.coordinator.refresh(latitude: 0, longitude: 0, anchorIsLiveFix: true)

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

        _ = await setup.coordinator.refresh(latitude: 1.0, longitude: 2.0, anchorIsLiveFix: true)

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
        async let refreshResult = setup.coordinator.refresh(latitude: 1.0, longitude: 2.0, anchorIsLiveFix: true)
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

        let first = await setup.coordinator.refresh(latitude: 1.0, longitude: 2.0, anchorIsLiveFix: true)
        #expect(first.errorOrNil == .noIdentifiedUser)

        // User signs in between calls.
        contextStore.setUserId("user-1")
        let second = await setup.coordinator.refresh(latitude: 1.0, longitude: 2.0, anchorIsLiveFix: true)

        #expect(second.isSuccess)
        #expect(api.fetchNearbyGeofencesCallsCount == 1)
    }

    // MARK: - handleMovement

    @Test
    func handleMovement_givenNoUserId_expectFailureAndNoApiCall() async {
        let storage = makeStorage()
        let setup = makeCoordinator(storage: storage, contextStore: makeContextStore(userId: nil))

        let result = await setup.coordinator.handleMovement(latitude: 1.0, longitude: 2.0, anchorIsLiveFix: true)

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

        let result = await setup.coordinator.handleMovement(latitude: 1.0, longitude: 2.0, anchorIsLiveFix: true)

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
        let result = await setup.coordinator.handleMovement(latitude: 0, longitude: 0.001, anchorIsLiveFix: true)

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
        let result = await setup.coordinator.handleMovement(latitude: 0, longitude: 0.001, anchorIsLiveFix: true)

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
        let result = await setup.coordinator.handleMovement(latitude: 1.0, longitude: 1.0, anchorIsLiveFix: true)

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
        let result = await setup.coordinator.refresh(latitude: 1.0, longitude: 1.0, anchorIsLiveFix: true)

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

        _ = await setup.coordinator.handleMovement(latitude: 0, longitude: 0.001, anchorIsLiveFix: true)

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
        _ = await setup.coordinator.handleMovement(latitude: newLocation.latitude, longitude: newLocation.longitude, anchorIsLiveFix: true)

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
        _ = await setup.coordinator.handleMovement(latitude: newLocation.latitude, longitude: newLocation.longitude, anchorIsLiveFix: true)

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
        let result = await setup.coordinator.handleMovement(latitude: newLocation.latitude, longitude: newLocation.longitude, anchorIsLiveFix: true)

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

        let result = await setup.coordinator.handleMovement(latitude: 1.0, longitude: 1.0, anchorIsLiveFix: true)

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
        _ = await setup.coordinator.refresh(latitude: 0, longitude: 0, anchorIsLiveFix: true)
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
        let result = await setup.coordinator.handleMovement(latitude: newLocation.latitude, longitude: newLocation.longitude, anchorIsLiveFix: true)

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
        _ = await setup.coordinator.handleMovement(latitude: 0, longitude: 0.001, anchorIsLiveFix: true)

        let trigger = setup.monitor.startedRegions
            .last { $0.identifier == GeofenceConstants.movementTriggerIdentifier }
        #expect(trigger?.radius == GeofenceConstants.polygonWakeMinRadius, "got \(String(describing: trigger?.radius))")
        // And the circle-only control: no polygon means the configured radius, untouched.
        let circleStorage = makeStorage()
        let circleSetup = await makeRegisteredSetup(
            regions: [makeRegion(id: "c1", latitude: 0, longitude: 0)], config: diffConfig, storage: circleStorage
        )
        _ = await circleSetup.coordinator.handleMovement(latitude: 0, longitude: 0.001, anchorIsLiveFix: true)
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
        let result = await setup.coordinator.handleMovement(latitude: newLocation.latitude, longitude: newLocation.longitude, anchorIsLiveFix: true)

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

        let result = await setup.coordinator.handleMovement(latitude: 0, longitude: 0.001, anchorIsLiveFix: true)

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
        let result = await setup.coordinator.handleMovement(latitude: 0, longitude: 0.02, anchorIsLiveFix: true)

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
        let result = await setup.coordinator.handleMovement(latitude: 0, longitude: 0.02, anchorIsLiveFix: true)

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
        _ = await setup.coordinator.refresh(latitude: 0, longitude: 0, anchorIsLiveFix: true)

        let result = await setup.coordinator.handleMovement(latitude: 0, longitude: 0.001, anchorIsLiveFix: true)

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

        let result = await setup.coordinator.handleMovement(latitude: 0, longitude: 0.001, anchorIsLiveFix: true)

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

        _ = await setup.coordinator.refresh(latitude: 0, longitude: 0, anchorIsLiveFix: true)

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

        _ = await setup.coordinator.refresh(latitude: 0, longitude: 0, anchorIsLiveFix: true)

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

        let result = await setup.coordinator.refresh(latitude: 0.02, longitude: 0, anchorIsLiveFix: true)

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
        let result = await setup.coordinator.refresh(latitude: 0.02, longitude: 0, anchorIsLiveFix: true)

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
        let result = await setup.coordinator.handleMovement(latitude: newLocation.latitude, longitude: newLocation.longitude, anchorIsLiveFix: true)

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
        _ = await setup.coordinator.refresh(latitude: 0, longitude: 0, anchorIsLiveFix: true)

        let result = await setup.coordinator.handleMovement(latitude: 0, longitude: 0.05, anchorIsLiveFix: true)

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
        let result = await setup.coordinator.handleMovement(latitude: newLocation.latitude, longitude: newLocation.longitude, anchorIsLiveFix: true)

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

        async let firstRefresh = setup.coordinator.refresh(latitude: 0, longitude: 0, anchorIsLiveFix: true)
        await arrived.wait()
        let movement = await setup.coordinator.handleMovement(latitude: 0, longitude: 0, anchorIsLiveFix: true)
        await suspendUntil.fire()
        _ = await firstRefresh

        #expect(movement.errorOrNil == .alreadyInProgress)
    }

    /// The recovery half of `handleMovement_givenInFlightRefresh_expectAlreadyInProgress`.
    ///
    /// Short-circuiting on the gate is correct; LOSING the pass is not. A business crossing and a
    /// trigger EXIT routinely arrive from the same movement, and the movement pass is the only
    /// thing that re-centres the trigger — dropped, the trigger stays on the circle the device
    /// just left, where no further EXIT can ever fire. So the loser must be replayed once the
    /// holder releases.
    @Test
    func handleMovement_givenItLostTheGateToARefresh_expectItIsReplayedAfterwards() async {
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

        async let firstRefresh = setup.coordinator.refresh(latitude: 0, longitude: 0, anchorIsLiveFix: true)
        await arrived.wait()
        // Deliberately elsewhere, so a trigger re-armed at these coordinates can only have come
        // from the replay and not from the refresh that beat it.
        let movement = await setup.coordinator.handleMovement(latitude: 0, longitude: 0.05, anchorIsLiveFix: true)
        await suspendUntil.fire()
        _ = await firstRefresh

        #expect(movement.errorOrNil == .alreadyInProgress)

        let movedTo = LocationData(latitude: 0, longitude: 0.05)
        for _ in 0 ..< 200 {
            if setup.monitor.startedRegions.contains(where: {
                $0.identifier == GeofenceConstants.movementTriggerIdentifier && $0.center == movedTo
            }) { break }
            try? await Task.sleep(nanoseconds: 10000000)
        }
        let triggerStarts = setup.monitor.startedRegions.filter { $0.identifier == GeofenceConstants.movementTriggerIdentifier }
        #expect(triggerStarts.last?.center == movedTo)
    }

    /// The two-step window: `acquireGate()` answering false and the record landing were separate,
    /// so a holder could release AND drain between them. The record then arrived with the gate
    /// already free and nothing left due to drain it, stranding the trigger on the circle the
    /// device had just exited.
    ///
    /// Asserted as an invariant rather than by racing threads. The window is microseconds wide, so
    /// a thread race would pass against the broken code on nearly every run and prove nothing; the
    /// invariant it violates is checkable exactly. A call that TAKES the gate must leave no
    /// deferral behind, and a call that does not take it must leave exactly one.
    @Test
    func acquireGateOrDefer_givenAFreeGate_expectItIsTakenAndAnyQueuedMovementSuperseded() async {
        let setup = await makeRegisteredSetup(regions: [], config: diffConfig, storage: makeStorage())
        // Seeded, not left nil: starting from nil the assertion below holds even if the supersede
        // clear sits OUTSIDE the critical section, which is the bug this test has to be able to
        // see. A winner must clear a queued movement in the same section that took the gate.
        setup.coordinator.deferredMovement.wrappedValue = GeofenceSyncCoordinatorImpl.DeferredMovement(
            latitude: 9, longitude: 9, anchorIsLiveFix: true, sequence: 1
        )

        let taken = setup.coordinator.acquireGateOrDefer(
            latitude: 1, longitude: 2, anchorIsLiveFix: true,
            replaySequence: 2
        )

        // The replay's OWN sequence, not merely "taken": `handleMovement` publishes what comes
        // back as applied, so a freshly minted one here would outrank a newer queued movement.
        #expect(taken == .taken(sequence: 2))
        // A deferral surviving here is either never drained, or drained after this pass and so
        // moves the trigger back to coordinates the device has already left.
        #expect(setup.coordinator.deferredMovement.wrappedValue?.latitude == nil)
        setup.coordinator.releaseGate()
    }

    /// The other half: losing the gate must record, in the same critical section that observed the
    /// gate held.
    @Test
    func acquireGateOrDefer_givenAHeldGate_expectTheMovementIsRecorded() async {
        let setup = await makeRegisteredSetup(regions: [], config: diffConfig, storage: makeStorage())
        #expect(setup.coordinator.acquireGate())

        // From the allocator, not a literal: the registration in `makeRegisteredSetup` now plants
        // the trigger and applies a sequence of its own, so a hand-picked 1 is already spent and
        // the call is refused as overtaken — an ordering production cannot produce.
        let taken = setup.coordinator.acquireGateOrDefer(
            latitude: 3, longitude: 4, anchorIsLiveFix: false,
            replaySequence: setup.coordinator.nextMovementSequence()
        )

        #expect(taken == .deferred)
        #expect(setup.coordinator.deferredMovement.wrappedValue?.latitude == 3)
        #expect(setup.coordinator.deferredMovement.wrappedValue?.anchorIsLiveFix == false)
        setup.coordinator.releaseGate()
    }

    /// A movement that runs must supersede an older one still queued, or the replay moves the
    /// trigger BACK to coordinates the device has already left.
    @Test
    func handleMovement_givenANewerMovementRanFirst_expectTheStaleDeferralDropped() async {
        let storage = makeStorage()
        let setup = await makeRegisteredSetup(regions: [], config: diffConfig, storage: storage)

        // Queue a stale movement by hand, as a losing pass would have.
        setup.coordinator.deferredMovement.wrappedValue = GeofenceSyncCoordinatorImpl.DeferredMovement(
            latitude: 0, longitude: 0, anchorIsLiveFix: true, sequence: 1
        )
        let newer = LocationData(latitude: 0, longitude: 0.05)
        _ = await setup.coordinator.handleMovement(
            latitude: newer.latitude, longitude: newer.longitude, anchorIsLiveFix: true
        )
        for _ in 0 ..< 50 {
            await Task.yield()
        }

        let triggerStarts = setup.monitor.startedRegions.filter { $0.identifier == GeofenceConstants.movementTriggerIdentifier }
        #expect(triggerStarts.last?.center == newer)
    }

    /// A drained replay must not re-centre the trigger behind a movement that already ran.
    ///
    /// `drainDeferredMovement` clears the queue and frees the gate BEFORE its replay task starts,
    /// so a newer movement can take that gate and re-centre first. Replaying afterwards moved the
    /// trigger back to the older coordinates — the exact loss the deferral exists to prevent,
    /// reached from the other side.
    ///
    /// Driven through the real gate rather than by racing tasks: the replay is retired on an
    /// arrival-order comparison, so the ordering can be set up exactly instead of hoped for.
    @Test
    func drainDeferredMovement_givenANewerMovementAlreadyRan_expectTheReplayDiscarded() async {
        let setup = await makeRegisteredSetup(regions: [], config: diffConfig, storage: makeStorage())
        let stale = GeofenceSyncCoordinatorImpl.DeferredMovement(
            latitude: 0, longitude: 0, anchorIsLiveFix: true, sequence: 1
        )

        // The newer movement arrives and completes first, as it would by taking the freed gate.
        let newer = LocationData(latitude: 0, longitude: 0.05)
        _ = await setup.coordinator.handleMovement(
            latitude: newer.latitude, longitude: newer.longitude, anchorIsLiveFix: true
        )
        // Queued after that pass, standing in for the copy a drain has ALREADY taken off the
        // queue — the winner's supersede clear cannot reach it, which is why the comparison at
        // replay time is the thing under test.
        setup.coordinator.deferredMovement.wrappedValue = stale
        setup.coordinator.drainDeferredMovement(userChanged: false)
        try? await Task.sleep(nanoseconds: 300000000)

        let triggerStarts = setup.monitor.startedRegions.filter { $0.identifier == GeofenceConstants.movementTriggerIdentifier }
        #expect(triggerStarts.last?.center == newer)
    }

    /// Built with `makeCoordinator`, not `makeRegisteredSetup`: these three drive the gate
    /// directly, and a registration pass leaves a trailing `drainDeferredMovement` that can clear
    /// a seeded deferral part-way through the assertions.
    ///
    /// The staleness test belongs INSIDE the gate's critical section.
    ///
    /// Checking before acquiring is the same two-step shape this gate exists to close: a newer
    /// movement can take the gate, re-centre and publish its sequence between the check and the
    /// acquisition, and the replay then runs at coordinates already superseded.
    @Test
    func acquireGateOrDefer_givenANewerMovementAlreadyApplied_expectOvertaken() {
        let setup = makeCoordinator(storage: makeStorage())
        setup.coordinator.noteMovementApplied(5)

        let outcome = setup.coordinator.acquireGateOrDefer(
            latitude: 1, longitude: 2, anchorIsLiveFix: true,
            replaySequence: 3
        )

        #expect(outcome == .overtaken)
        // Refused outright, not queued: a drain would only replay it into the same refusal.
        #expect(setup.coordinator.deferredMovement.wrappedValue == nil)
    }

    /// A fresh arrival outranks everything applied, so the staleness test must never catch one.
    ///
    /// The guarantee is that every applied sequence was issued by `nextMovementSequence`, which is
    /// monotonic — so the next issue always postdates the highest applied. Driven through the
    /// allocator here rather than with a literal, because a hand-picked `applied` value that the
    /// allocator has not reached tests an ordering production cannot produce.
    @Test
    func acquireGateOrDefer_givenAFreshArrivalAfterAnAppliedPass_expectItIsTaken() {
        let setup = makeCoordinator(storage: makeStorage())
        setup.coordinator.noteMovementApplied(setup.coordinator.nextMovementSequence())

        let replay = setup.coordinator.nextMovementSequence()
        let outcome = setup.coordinator.acquireGateOrDefer(
            latitude: 1, longitude: 2, anchorIsLiveFix: true,
            replaySequence: replay
        )

        #expect(outcome == .taken(sequence: replay))
        setup.coordinator.releaseGate()
    }

    /// Losing the gate must not demote the queue. A replay carries its ORIGINAL sequence, so it
    /// can arrive here after a newer movement has already queued — last-writer-wins would put the
    /// older coordinates back in front and the drain would re-centre to them.
    @Test
    func acquireGateOrDefer_givenAQueuedNewerMovement_expectAnOlderReplayDoesNotReplaceIt() {
        let setup = makeCoordinator(storage: makeStorage())
        #expect(setup.coordinator.acquireGate())
        setup.coordinator.deferredMovement.wrappedValue = GeofenceSyncCoordinatorImpl.DeferredMovement(
            latitude: 0, longitude: 0.05, anchorIsLiveFix: true, sequence: 2
        )

        let outcome = setup.coordinator.acquireGateOrDefer(
            latitude: 0, longitude: 0, anchorIsLiveFix: true,
            replaySequence: 1
        )

        #expect(outcome == .deferred)
        #expect(setup.coordinator.deferredMovement.wrappedValue?.sequence == 2)
        #expect(setup.coordinator.deferredMovement.wrappedValue?.longitude == 0.05)
        setup.coordinator.releaseGate()
    }

    /// A pass that failed re-centred nothing, so it must not claim to have done so — otherwise it
    /// retires a deferral that is still the best information available and the trigger is left
    /// wherever it already was.
    @Test
    func handleMovement_givenTheMovementFailed_expectNoReCentreClaimed() async {
        let contextStore = makeContextStore(userId: nil)
        let setup = makeCoordinator(storage: makeStorage(), contextStore: contextStore)

        let result = await setup.coordinator.handleMovement(
            latitude: 0, longitude: 0.05, anchorIsLiveFix: true
        )

        #expect(result.errorOrNil == .noIdentifiedUser)
        #expect(setup.coordinator.appliedMovementSequence.wrappedValue == 0)
    }

    /// The mirror of the held-gate case. A replay can acquire a briefly free gate while a NEWER
    /// arrival is already queued behind it; clearing the queue unconditionally drops that arrival
    /// outright, and the trigger ends at the replay's older coordinates.
    @Test
    func acquireGateOrDefer_givenAQueuedNewerMovement_expectAFreeGateDoesNotClearIt() {
        let setup = makeCoordinator(storage: makeStorage())
        setup.coordinator.deferredMovement.wrappedValue = GeofenceSyncCoordinatorImpl.DeferredMovement(
            latitude: 0, longitude: 0.05, anchorIsLiveFix: true, sequence: 2
        )

        let outcome = setup.coordinator.acquireGateOrDefer(
            latitude: 0, longitude: 0, anchorIsLiveFix: true,
            replaySequence: 1
        )

        #expect(outcome == .taken(sequence: 1))
        #expect(setup.coordinator.deferredMovement.wrappedValue?.sequence == 2)
        setup.coordinator.releaseGate()
    }

    /// A pass this one outranks IS superseded, or every winner would leave its own loser queued
    /// and the trigger would be walked back to it.
    @Test
    func acquireGateOrDefer_givenAQueuedOlderMovement_expectAFreeGateClearsIt() {
        let setup = makeCoordinator(storage: makeStorage())
        setup.coordinator.deferredMovement.wrappedValue = GeofenceSyncCoordinatorImpl.DeferredMovement(
            latitude: 0, longitude: 0, anchorIsLiveFix: true, sequence: 1
        )

        let outcome = setup.coordinator.acquireGateOrDefer(
            latitude: 0, longitude: 0.05, anchorIsLiveFix: true,
            replaySequence: 2
        )

        #expect(outcome == .taken(sequence: 2))
        #expect(setup.coordinator.deferredMovement.wrappedValue == nil)
        setup.coordinator.releaseGate()
    }

    /// Success is the wrong signal for "the trigger moved". A failed remote refresh re-arms from
    /// cache before returning its failure, and that re-centre is exactly what an older replay must
    /// not undo — so the pass has to claim it despite reporting failure.
    @Test
    func handleMovement_givenAFailedFetchThatReArmed_expectTheReCentreIsClaimed() async {
        let storage = makeStorage()
        await storage.setCachedGeofences([makeRegion(id: "a", latitude: 0, longitude: 0)])
        await storage.setCachedConfig(.fallback)
        let api = GeofenceApiServiceMock()
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            completion(.failure(.transport))
        }
        // No recorded sync, so the no-anchor branch takes the remote path and then re-arms.
        let setup = makeCoordinator(api: api, storage: storage)

        let result = await setup.coordinator.handleMovement(
            latitude: 0, longitude: 0.05, anchorIsLiveFix: true
        )

        #expect(!result.isSuccess)
        #expect(setup.coordinator.appliedMovementSequence.wrappedValue == 1)
    }

    /// A reset must not leave an old profile's movement behind it.
    ///
    /// The discard and the release have to happen together: with two steps a movement publishes
    /// between them, finds the gate still held, queues itself, and outlives the reset — a later
    /// drain then re-centres the trigger to the signed-out profile's coordinates.
    @Test
    func discardDeferredAndReleaseGate_expectTheQueueClearedAndTheGateFree() {
        let setup = makeCoordinator(storage: makeStorage())
        #expect(setup.coordinator.acquireGate())
        setup.coordinator.deferredMovement.wrappedValue = GeofenceSyncCoordinatorImpl.DeferredMovement(
            latitude: 0, longitude: 0.01, anchorIsLiveFix: true, sequence: 1
        )

        setup.coordinator.discardDeferredAndReleaseGate()

        #expect(setup.coordinator.deferredMovement.wrappedValue == nil)
        // Free, not merely flagged: the next movement takes it instead of queueing behind it.
        let next = setup.coordinator.acquireGateOrDefer(
            latitude: 0, longitude: 0.1, anchorIsLiveFix: true,
            replaySequence: 2
        )
        #expect(next == .taken(sequence: 2))
        setup.coordinator.releaseGate()
    }

    /// The same, through `reset` itself.
    @Test
    func reset_givenAQueuedMovement_expectItDiscardedAndTheGateFree() async {
        let storage = makeStorage()
        let setup = makeCoordinator(storage: storage, contextStore: makeContextStore(userId: nil))
        setup.coordinator.deferredMovement.wrappedValue = GeofenceSyncCoordinatorImpl.DeferredMovement(
            latitude: 0, longitude: 0.01, anchorIsLiveFix: true, sequence: 1
        )

        _ = await setup.coordinator.reset()

        #expect(setup.coordinator.deferredMovement.wrappedValue == nil)
        #expect(setup.coordinator.acquireGate())
        setup.coordinator.releaseGate()
    }

    /// A refresh re-centres the trigger too, and a replay that does not know it happened walks
    /// the trigger back. Found in peer review: the sequence only covered `handleMovement`, so
    /// every other entry point that plants the trigger was invisible to the overtaken check.
    @Test
    func refresh_givenItReCentred_expectTheReCentreRecorded() async {
        let storage = makeStorage()
        await storage.setCachedConfig(.fallback)
        let api = GeofenceApiServiceMock()
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            completion(.success(makeApiResponse(regions: [])))
        }
        let setup = makeCoordinator(api: api, storage: storage)

        _ = await setup.coordinator.refresh(latitude: 0, longitude: 0.05, anchorIsLiveFix: true)

        #expect(setup.coordinator.appliedMovementSequence.wrappedValue > 0)
    }

    /// The freshness skip moves nothing, so it must not retire a movement waiting behind it.
    @Test
    func refresh_givenTheFreshnessSkip_expectNoReCentreRecorded() async {
        let storage = makeStorage()
        await storage.setCachedConfig(.fallback)
        // A sync at the same place moments ago puts the next refresh on the skip branch.
        await storage.recordSync(timestamp: Date(), location: LocationData(latitude: 0, longitude: 0))
        let setup = makeCoordinator(storage: storage)

        _ = await setup.coordinator.refresh(latitude: 0, longitude: 0, anchorIsLiveFix: true)

        #expect(setup.coordinator.appliedMovementSequence.wrappedValue == 0)
    }

    /// The interleaving peer review described, end to end: a refresh lands between a drain and its
    /// replay, and the replay must not undo it.
    @Test
    func drainDeferredMovement_givenARefreshReCentredFirst_expectTheReplayDiscarded() async {
        let storage = makeStorage()
        await storage.setCachedConfig(.fallback)
        let api = GeofenceApiServiceMock()
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            completion(.success(makeApiResponse(regions: [])))
        }
        let setup = makeCoordinator(api: api, storage: storage)
        // Queued behind work that has since finished, as a drained-but-not-yet-run replay is.
        let stale = GeofenceSyncCoordinatorImpl.DeferredMovement(
            latitude: 0, longitude: 0, anchorIsLiveFix: true,
            sequence: setup.coordinator.nextMovementSequence()
        )

        _ = await setup.coordinator.refresh(latitude: 0, longitude: 0.05, anchorIsLiveFix: true)
        setup.coordinator.deferredMovement.wrappedValue = stale

        let outcome = setup.coordinator.acquireGateOrDefer(
            latitude: stale.latitude, longitude: stale.longitude,
            anchorIsLiveFix: stale.anchorIsLiveFix, replaySequence: stale.sequence
        )

        #expect(outcome == .overtaken)
    }

    /// Whoever takes the gate first must hold the earlier sequence.
    ///
    /// Allocating after the acquisition inverts that: a movement arriving in the gap allocates
    /// first, carries the LOWER sequence, and is then retired as overtaken by the refresh that was
    /// already running — so the trigger finishes at the older coordinates.
    @Test
    func acquireGateWithSequence_expectTheSequenceIsTakenWithTheGate() {
        let setup = makeCoordinator(storage: makeStorage())

        guard let held = setup.coordinator.acquireGateWithSequence() else {
            Issue.record("expected the free gate to be taken")
            return
        }
        // A movement arriving while the gate is held must outrank the holder, not trail it.
        let arrival = setup.coordinator.nextMovementSequence()

        #expect(arrival > held)
        // And the gate really is held, so that arrival defers rather than running.
        #expect(!setup.coordinator.acquireGate())
        setup.coordinator.releaseGate()
    }

    /// The inversion where it is actually reachable: the cached restore's window spans the OS
    /// registration, so a movement arriving mid-registration is easy to place exactly.
    ///
    /// Allocating at the end ranks the restore ABOVE that movement and retires it, leaving the
    /// trigger on the restore's older anchor. Allocating with the gate ranks it below.
    @Test
    func applyCachedRegistration_givenAMovementArrivedMidRegistration_expectItOutranksTheRestore() async {
        let storage = makeStorage()
        let monitor = MockGeofenceRegionMonitor()
        let setup = makeCoordinator(storage: storage, monitor: monitor)
        var arrival: UInt64 = 0
        // Stands in for a movement landing while the restore is talking to the OS.
        monitor.onStartMonitoring = { [weak coordinator = setup.coordinator] in
            guard arrival == 0, let coordinator else { return }
            arrival = coordinator.nextMovementSequence()
        }

        _ = await MainActor.run {
            setup.coordinator.applyCachedRegistration(
                cachedRegions: [makeRegion(id: "a", latitude: 0, longitude: 0)],
                anchor: LocationData(latitude: 0, longitude: 0),
                config: .fallback,
                userId: "user-1"
            )
        }

        #expect(arrival > 0)
        #expect(arrival > setup.coordinator.appliedMovementSequence.wrappedValue)
    }

    /// The same intent through `refresh`. Stated plainly: this does NOT discriminate the fix —
    /// `refresh`'s acquire and allocate are adjacent synchronous statements with no suspension
    /// between them, so a test cannot land inside that window. It pins the ordering the fix
    /// guarantees; the restore test above is the one that fails without it.
    @Test
    func refresh_givenAMovementQueuedWhileItRan_expectTheMovementOutranksIt() async {
        let storage = makeStorage()
        await storage.setCachedConfig(.fallback)
        let api = GeofenceApiServiceMock()
        let reachedApi = AsyncSignal()
        let release = AsyncSignal()
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            Task {
                await reachedApi.fire()
                await release.wait()
                completion(.success(makeApiResponse(regions: [])))
            }
        }
        let setup = makeCoordinator(api: api, storage: storage)

        async let running = setup.coordinator.refresh(latitude: 0, longitude: 0.01, anchorIsLiveFix: true)
        await reachedApi.wait()
        // Arrives mid-refresh, so it is newer and must not be retired by the refresh.
        let queued = await setup.coordinator.handleMovement(latitude: 0, longitude: 0.02, anchorIsLiveFix: true)
        // Captured while the refresh still holds the gate: its release drains the queue.
        let deferredSequence = setup.coordinator.deferredMovement.wrappedValue?.sequence ?? 0
        #expect(setup.coordinator.deferredMovement.wrappedValue?.longitude == 0.02)
        await release.fire()
        _ = await running

        #expect(queued.errorOrNil == .alreadyInProgress)
        #expect(deferredSequence > 0)
        // Compared after the refresh has applied its own: with the allocation split from the
        // acquisition the refresh takes the HIGHER number and retires this movement, so the
        // trigger keeps the refresh's older coordinates. Read from the captured sequence, not
        // from the queue, because the refresh's release drains it on the way out.
        #expect(deferredSequence > setup.coordinator.appliedMovementSequence.wrappedValue)
    }

    /// A live movement must never be refused as overtaken.
    ///
    /// Minting the sequence before the gate lets a pass that acquires LATER hold an earlier
    /// number: the movement allocates, something else takes the free gate and re-centres with the
    /// next sequence, and the movement then reaches the gate and is dropped — work the code
    /// without any sequence would have run. Stamping inside the gate makes "took the gate later"
    /// and "holds the later sequence" the same statement.
    @Test
    func acquireGateOrDefer_givenAFreshMovementAfterAnApplied_expectItIsNeverOvertaken() {
        let setup = makeCoordinator(storage: makeStorage())
        // Something already re-centred and published a sequence.
        guard case .taken(let earlier) = setup.coordinator.acquireGateOrDefer(
            latitude: 0, longitude: 0, anchorIsLiveFix: true, replaySequence: nil
        ) else {
            Issue.record("expected the free gate to be taken")
            return
        }
        setup.coordinator.noteMovementApplied(earlier)
        setup.coordinator.releaseGate()

        let outcome = setup.coordinator.acquireGateOrDefer(
            latitude: 0, longitude: 0.05, anchorIsLiveFix: true, replaySequence: nil
        )

        guard case .taken(let fresh) = outcome else {
            Issue.record("a fresh movement must never be overtaken, got \(outcome)")
            return
        }
        #expect(fresh > earlier)
        setup.coordinator.releaseGate()
    }

    /// A replay, by contrast, still is retired once something newer has re-centred.
    @Test
    func acquireGateOrDefer_givenAReplayOlderThanTheApplied_expectOvertaken() {
        let setup = makeCoordinator(storage: makeStorage())
        let old = setup.coordinator.nextMovementSequence()
        setup.coordinator.noteMovementApplied(setup.coordinator.nextMovementSequence())

        let outcome = setup.coordinator.acquireGateOrDefer(
            latitude: 0, longitude: 0, anchorIsLiveFix: true, replaySequence: old
        )

        #expect(outcome == .overtaken)
    }

    // MARK: - Teardown ordering

    /// Teardown clears user-scoped state and stops the OS, and the two are separate awaits. A
    /// polygon pass resuming between them reads a still-populated `monitoredGeofenceIds`, passes
    /// the create guard in `recordPolygonMembership`, and emits an enter for a fence being torn
    /// down. Clearing first makes such a pass fail closed.
    ///
    /// Asserted as an order, not by racing a pass into the gap: the gap is one suspension wide and
    /// a racing test would pass against the wrong ordering on almost every run. Both steps record
    /// onto one timeline because neither can observe the other — the clear is `async`, the stop is
    /// `@MainActor`.
    @Test
    func reset_expectUserScopedStateClearedBeforeTheOsStop() async {
        let recorder = TeardownOrderRecorder()
        let backing = makeStorage()
        let spy = SpyGeofenceSyncStorage(
            underlying: backing,
            onClearUserScopedState: { recorder.record("clear") }
        )
        let monitor = MockGeofenceRegionMonitor()
        monitor.onStopAll = { recorder.record("stop") }
        let contextStore = makeContextStore(userId: nil)
        let setup = makeCoordinator(storage: spy, monitor: monitor, contextStore: contextStore)

        _ = await setup.coordinator.reset()

        #expect(recorder.recorded == ["clear", "stop"])
    }

    /// The same ordering at the other teardown site. A user switch landing inside a gated operation
    /// tears down through `cleanupIfUserChanged` rather than `reset`, and the window is identical.
    @Test
    func handleMovement_givenUserChangedMidFlight_expectStateClearedBeforeTheOsStop() async {
        let recorder = TeardownOrderRecorder()
        let backing = makeStorage()
        let contextStore = makeContextStore(userId: "user-1")
        // Flipped inside the freshness read, so the operation completes for `user-1` and finds a
        // different user at its single gated exit.
        let spy = SpyGeofenceSyncStorage(
            underlying: backing,
            onGetLastSync: { contextStore.setUserId("user-2") },
            onClearUserScopedState: { recorder.record("clear") }
        )
        let monitor = MockGeofenceRegionMonitor()
        monitor.onStopAll = { recorder.record("stop") }
        // The API mock never calls its completion unless given a closure, and the no-anchor path
        // takes the remote branch — without this the pass suspends forever and hangs the suite.
        let api = GeofenceApiServiceMock()
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            completion(.success(makeApiResponse(regions: [], config: diffConfig)))
        }
        let setup = makeCoordinator(api: api, storage: spy, monitor: monitor, contextStore: contextStore)

        _ = await setup.coordinator.handleMovement(latitude: 0, longitude: 0.001, anchorIsLiveFix: true)

        #expect(recorder.recorded == ["clear", "stop"])
    }

    /// What the ordering buys, pinned at the layer that enforces it: once the clear has run, the
    /// create guard refuses a belief for a fence that is no longer monitored. This is what a pass
    /// resuming after the clear hits, and it is why clearing first fails closed.
    @Test
    func recordPolygonMembership_givenStateAlreadyCleared_expectSuppressedRatherThanAnEnter() async {
        let storage = makeStorage()
        await storage.recordRegistration(
            center: LocationData(latitude: 0, longitude: 0), businessIds: ["poly-1"]
        )
        await storage.clearUserScopedState()

        let outcome = await storage.recordPolygonMembership(.inside, forIdentifier: "poly-1")

        #expect(outcome == .suppressedUnmonitored)
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

        async let firstRefresh = setup.coordinator.refresh(latitude: 0, longitude: 0, anchorIsLiveFix: true)
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

        async let refreshResult = setup.coordinator.refresh(latitude: 0, longitude: 0, anchorIsLiveFix: true)
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

        async let refreshResult = setup.coordinator.refresh(latitude: 0, longitude: 0, anchorIsLiveFix: true)
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

        async let firstMovement = setup.coordinator.handleMovement(latitude: 0, longitude: 0, anchorIsLiveFix: true)
        await arrived.wait()
        let refreshResult = await setup.coordinator.refresh(latitude: 0, longitude: 0, anchorIsLiveFix: true)
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

        _ = await setup.coordinator.refresh(latitude: anchor.latitude, longitude: anchor.longitude, anchorIsLiveFix: true)

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

        _ = await setup.coordinator.refresh(latitude: anchor.latitude, longitude: anchor.longitude, anchorIsLiveFix: true)

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

        _ = await setup.coordinator.refresh(latitude: anchor.latitude, longitude: anchor.longitude, anchorIsLiveFix: true)

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

        _ = await setup.coordinator.refresh(latitude: anchor.latitude, longitude: anchor.longitude, anchorIsLiveFix: true)

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
        _ = await setup.coordinator.refresh(latitude: anchor.latitude, longitude: anchor.longitude, anchorIsLiveFix: true)
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

        _ = await setup.coordinator.refresh(latitude: anchor.latitude, longitude: anchor.longitude, anchorIsLiveFix: true)

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

        _ = await setup.coordinator.refresh(latitude: anchor.latitude, longitude: anchor.longitude, anchorIsLiveFix: true)

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

        _ = await setup.coordinator.refresh(latitude: 0, longitude: 0, anchorIsLiveFix: true)
        #expect(setup.monitor.monitoredRegionIdentifiers.contains("g1"))

        // Same id, different circle, and the monitor now refuses it.
        await storage.setCachedGeofences([makeRegion(id: "g1", latitude: 0.001, longitude: 0, radius: 900)])
        setup.monitor.rejectedIdentifiers = ["g1"]
        _ = await setup.coordinator.handleMovement(latitude: 0, longitude: 0.001, anchorIsLiveFix: true)

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

        _ = await setup.coordinator.refresh(latitude: anchor.latitude, longitude: anchor.longitude, anchorIsLiveFix: true)

        await awaitEmits(setup.emitter, count: 0)
        #expect(setup.emitter.calls.wrappedValue.isEmpty)
    }

    /// Nothing crossed anything on this path, so the event time is when the sync noticed — read
    /// from the injected clock, not the wall clock the tracker used to stamp with.
    @Test
    func refresh_givenNewInsideFences_expectStampedFromTheInjectedClock() async {
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
        let setup = makeCoordinator(api: api, storage: storage, dateUtil: dateUtil)

        _ = await setup.coordinator.refresh(latitude: anchor.latitude, longitude: anchor.longitude, anchorIsLiveFix: true)

        await awaitEmits(setup.emitter, count: 2)
        let stamps = setup.emitter.calls.wrappedValue.map(\.occurredAt)
        #expect(stamps.count == 2)
        #expect(stamps.allSatisfy { $0 == dateUtil.givenNow })
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

        _ = await setup.coordinator.refresh(latitude: anchor.latitude, longitude: anchor.longitude, anchorIsLiveFix: true)

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

        let result = await setup.coordinator.refresh(latitude: 0, longitude: 0, anchorIsLiveFix: true)

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

        let result = await setup.coordinator.refresh(latitude: 0, longitude: 0, anchorIsLiveFix: true)

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

        let result = await setup.coordinator.refresh(latitude: 0, longitude: 0, anchorIsLiveFix: true)

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

        let refreshTask = Task { await setup.coordinator.refresh(latitude: 0, longitude: 0, anchorIsLiveFix: true) }
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

        let result = await setup.coordinator.refresh(latitude: 0, longitude: 0, anchorIsLiveFix: true)
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
    /// Runs at the start of `clearUserScopedState`, so a teardown test can put the clear on the
    /// same timeline as the OS stop and assert their order.
    private let onClearUserScopedState: (@Sendable () -> Void)?

    init(
        underlying: GeofenceStorage,
        onSetCachedGeofences: (@Sendable () -> Void)? = nil,
        onGetLastSync: (@Sendable () -> Void)? = nil,
        onClearUserScopedState: (@Sendable () -> Void)? = nil
    ) {
        self.underlying = underlying
        self.onSetCachedGeofences = onSetCachedGeofences
        self.onGetLastSync = onGetLastSync
        self.onClearUserScopedState = onClearUserScopedState
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
        onClearUserScopedState?()
        operations.append(.clearUserScopedState)
        await underlying.clearUserScopedState()
    }
}

// MARK: - Transition emitter spy

/// Records the synthetic transitions the coordinator fires for initial enter-when-inside.
private final class TransitionEmitterSpy: GeofenceTransitionEmitting, @unchecked Sendable {
    struct Emit: Equatable, Sendable {
        let geofenceId: String
        let transition: GeofenceTransition
        let occurredAt: Date
    }

    let calls = Synchronized<[Emit]>([])
    /// Invoked after each recorded emit with its 0-based index — lets a test mutate state mid-batch
    /// (e.g. change the identified user) to exercise the per-iteration guard.
    var onEmit: (@Sendable (Int) -> Void)?

    func trackTransition(geofenceId: String, transition: GeofenceTransition, occurredAt: Date) async {
        let index = calls.mutating { calls -> Int in
            calls.append(Emit(geofenceId: geofenceId, transition: transition, occurredAt: occurredAt))
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

/// Collects teardown steps from both isolation domains onto one ordered timeline.
private final class TeardownOrderRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var steps: [String] = []

    func record(_ step: String) {
        lock.lock()
        defer { lock.unlock() }
        steps.append(step)
    }

    var recorded: [String] {
        lock.lock()
        defer { lock.unlock() }
        return steps
    }
}
