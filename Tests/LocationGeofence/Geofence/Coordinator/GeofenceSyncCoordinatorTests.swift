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
        dwellCoordinator: GeofenceDwellCoordinator? = nil,
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
            dwellCoordinator: dwellCoordinator,
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
                metadata: region.metadata.isEmpty ? nil : region.metadata,
                dwellThresholdSeconds: region.dwellThresholdSeconds > 0 ? region.dwellThresholdSeconds : nil
            )
        }
        let apiConfig = config.map { config in
            GeofenceApiConfig(
                localRefreshTriggerRadius: config.localRefreshTriggerRadius,
                remoteFetchRefreshTriggerRadius: config.remoteFetchRefreshTriggerRadius,
                // Config stores seconds; the wire format is ms.
                remoteFetchRefreshExpiryTime: config.remoteFetchRefreshExpiry * 1000,
                duplicateEventsExpiryTime: config.duplicateEventsExpiry * 1000,
                maxMonitoringDistance: config.maxMonitoringDistance,
                ios: GeofenceApiPlatformConfig(maxBusinessGeofence: config.maxBusinessGeofences)
            )
        }
        return GeofenceApiResponse(config: apiConfig, geofences: apiRegions)
    }

    // MARK: - Catalog cached before dwell support

    /// State a pre-dwell SDK (integration base e6590003) left behind, as raw bytes rather than
    /// through the current encoder: a fresh sync, a registration around it, and a region with no
    /// `dwellThresholdSeconds`, which now decodes as dwell disabled.
    private struct LegacyFixture {
        let dir: URL
        let storage: GeofenceStorage
        let dateUtil: DateUtilStub
    }

    private func makeLegacyFixture() throws -> LegacyFixture {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let json = """
        {
          "cachedGeofences": [
            {
              "id": "legacy-1",
              "latitude": 37.0,
              "longitude": -122.0,
              "radius": 100,
              "name": "legacy-1",
              "transitionTypes": ["enter", "exit"],
              "lastUpdated": 1700000000,
              "geosetIds": [],
              "metadata": {}
            }
          ],
          "lastServerSyncLocation": {"latitude": 37.0, "longitude": -122.0},
          "lastServerSyncTimestamp": 1700000000,
          "monitoredGeofenceIds": ["legacy-1"],
          "movementTriggerCenter": {"latitude": 37.0, "longitude": -122.0},
          "cachedConfig": {
            "localRefreshTriggerRadius": 1000,
            "remoteFetchRefreshTriggerRadius": 3000,
            "remoteFetchRefreshExpiry": 3600,
            "duplicateEventsExpiry": 60,
            "maxBusinessGeofences": 10,
            "maxMonitoringDistance": 100000
          }
        }
        """
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: dir.appendingPathComponent("geofenceState.json"))
        let dateUtil = DateUtilStub()
        // 100 s after the recorded sync: fresh against the one-hour expiry.
        dateUtil.givenNow = Date(timeIntervalSince1970: 1700000100)
        return LegacyFixture(dir: dir, storage: GeofenceStorage(directoryURL: dir), dateUtil: dateUtil)
    }

    /// The legacy fixture's config as the server sends it now.
    private var legacyConfig: GeofenceConfig {
        GeofenceConfig(
            localRefreshTriggerRadius: 1000,
            remoteFetchRefreshTriggerRadius: 3000,
            remoteFetchRefreshExpiry: 3600,
            duplicateEventsExpiry: 60,
            maxBusinessGeofences: 10,
            maxMonitoringDistance: 100000
        )
    }

    /// The legacy fixture's region as the server sends it now.
    private func currentLegacyRegion(dwellThresholdSeconds: Int) -> Geofence {
        Geofence(
            id: "legacy-1",
            latitude: 37.0,
            longitude: -122.0,
            radius: 100,
            name: "legacy-1",
            transitionTypes: [.enter, .exit],
            lastUpdated: Date(timeIntervalSince1970: 1700000000),
            dwellThresholdSeconds: dwellThresholdSeconds
        )
    }

    private func cachedThresholds(_ storage: GeofenceStorage) async -> [Int] {
        await storage.getCachedGeofences().map(\.dwellThresholdSeconds)
    }

    @Test
    func refresh_givenFreshCatalogCachedBeforeDwell_expectOneFetchThenNoneAfterRelaunch() async throws {
        let fixture = try makeLegacyFixture()
        defer { try? FileManager.default.removeItem(at: fixture.dir) }
        let setup = makeCoordinator(storage: fixture.storage, dateUtil: fixture.dateUtil)
        let response = makeApiResponse(regions: [currentLegacyRegion(dwellThresholdSeconds: 60)], config: legacyConfig)
        setup.api.fetchNearbyGeofencesClosure = { _, _, completion in completion(.success(response)) }

        let result = await setup.coordinator.refresh(latitude: 37.0, longitude: -122.0, anchorIsLiveFix: true)

        #expect(result.errorOrNil == nil)
        #expect(setup.api.fetchNearbyGeofencesCallsCount == 1)
        #expect(await cachedThresholds(fixture.storage) == [60])

        // A new process on the same file: the catalog is current, so ordinary freshness applies.
        let relaunched = makeCoordinator(storage: GeofenceStorage(directoryURL: fixture.dir), dateUtil: fixture.dateUtil)
        _ = await relaunched.coordinator.refresh(latitude: 37.0, longitude: -122.0, anchorIsLiveFix: true)
        #expect(relaunched.api.fetchNearbyGeofencesCallsCount == 0)
    }

    @Test
    func refresh_givenCatalogCachedBeforeDwellAndServerSendsNoDwell_expectAcknowledgedAsCurrent() async throws {
        let fixture = try makeLegacyFixture()
        defer { try? FileManager.default.removeItem(at: fixture.dir) }
        let setup = makeCoordinator(storage: fixture.storage, dateUtil: fixture.dateUtil)
        let response = makeApiResponse(regions: [currentLegacyRegion(dwellThresholdSeconds: 0)], config: legacyConfig)
        setup.api.fetchNearbyGeofencesClosure = { _, _, completion in completion(.success(response)) }

        _ = await setup.coordinator.refresh(latitude: 37.0, longitude: -122.0, anchorIsLiveFix: true)

        #expect(setup.api.fetchNearbyGeofencesCallsCount == 1)
        #expect(await cachedThresholds(fixture.storage) == [0])
        // Dwell disabled by a current server is a real answer, not a reason to keep fetching.
        let relaunched = makeCoordinator(storage: GeofenceStorage(directoryURL: fixture.dir), dateUtil: fixture.dateUtil)
        _ = await relaunched.coordinator.refresh(latitude: 37.0, longitude: -122.0, anchorIsLiveFix: true)
        #expect(relaunched.api.fetchNearbyGeofencesCallsCount == 0)
    }

    @Test
    func refresh_givenCatalogCachedBeforeDwellAndFetchFails_expectStateUntouchedAndRetried() async throws {
        let fixture = try makeLegacyFixture()
        defer { try? FileManager.default.removeItem(at: fixture.dir) }
        let stateFile = fixture.dir.appendingPathComponent("geofenceState.json")
        let setup = makeCoordinator(storage: fixture.storage, dateUtil: fixture.dateUtil)
        setup.api.fetchNearbyGeofencesClosure = { _, _, completion in completion(.failure(.transport)) }
        let before = try Data(contentsOf: stateFile)

        let result = await setup.coordinator.refresh(latitude: 37.0, longitude: -122.0, anchorIsLiveFix: true)

        #expect(result.errorOrNil == .fetchFailed(.transport))
        #expect(setup.api.fetchNearbyGeofencesCallsCount == 1)
        // The pass would otherwise have skipped, which writes nothing.
        #expect(try Data(contentsOf: stateFile) == before)

        let response = makeApiResponse(regions: [currentLegacyRegion(dwellThresholdSeconds: 60)], config: legacyConfig)
        setup.api.fetchNearbyGeofencesClosure = { _, _, completion in completion(.success(response)) }
        _ = await setup.coordinator.refresh(latitude: 37.0, longitude: -122.0, anchorIsLiveFix: true)
        #expect(setup.api.fetchNearbyGeofencesCallsCount == 2)
        #expect(await cachedThresholds(fixture.storage) == [60])
    }

    @Test
    func refresh_givenCatalogCachedBeforeDwellFetchFailsBeyondLocalRadius_expectCachedRerankStillRuns() async throws {
        let fixture = try makeLegacyFixture()
        defer { try? FileManager.default.removeItem(at: fixture.dir) }
        let setup = makeCoordinator(storage: fixture.storage, dateUtil: fixture.dateUtil)
        setup.api.fetchNearbyGeofencesClosure = { _, _, completion in completion(.failure(.transport)) }

        // ~2 km north: beyond the 1 km local radius, inside the 3 km refetch radius.
        let result = await setup.coordinator.refresh(latitude: 37.018, longitude: -122.0, anchorIsLiveFix: true)

        #expect(result.errorOrNil == .fetchFailed(.transport))
        #expect(setup.api.fetchNearbyGeofencesCallsCount == 1)
        #expect(await fixture.storage.getLastRegistrationCenter()?.latitude == 37.018)
        #expect(await cachedThresholds(fixture.storage) == [0])
    }

    @Test
    func refresh_givenCatalogCachedBeforeDwellAndUnreadableResponse_expectCacheKeptAndRetried() async throws {
        let fixture = try makeLegacyFixture()
        defer { try? FileManager.default.removeItem(at: fixture.dir) }
        let setup = makeCoordinator(storage: fixture.storage, dateUtil: fixture.dateUtil)
        let unreadable = makeApiResponse(regions: [makeRegion(id: "broken", latitude: 91, longitude: -122)], config: legacyConfig)
        setup.api.fetchNearbyGeofencesClosure = { _, _, completion in completion(.success(unreadable)) }

        let result = await setup.coordinator.refresh(latitude: 37.0, longitude: -122.0, anchorIsLiveFix: true)

        #expect(result.errorOrNil == .fetchFailed(.decoding))
        #expect(setup.api.fetchNearbyGeofencesCallsCount == 1)
        #expect(await fixture.storage.getCachedGeofences().map(\.id) == ["legacy-1"])

        let response = makeApiResponse(regions: [currentLegacyRegion(dwellThresholdSeconds: 60)], config: legacyConfig)
        setup.api.fetchNearbyGeofencesClosure = { _, _, completion in completion(.success(response)) }
        _ = await setup.coordinator.refresh(latitude: 37.0, longitude: -122.0, anchorIsLiveFix: true)
        #expect(setup.api.fetchNearbyGeofencesCallsCount == 2)
        #expect(await cachedThresholds(fixture.storage) == [60])
    }

    @Test
    func refresh_givenCatalogCachedBeforeDwellAndUserChangesDuringFetch_expectResponseNotCached() async throws {
        let fixture = try makeLegacyFixture()
        defer { try? FileManager.default.removeItem(at: fixture.dir) }
        let setup = makeCoordinator(storage: fixture.storage, dateUtil: fixture.dateUtil)
        let contextStore = setup.contextStore
        let response = makeApiResponse(regions: [currentLegacyRegion(dwellThresholdSeconds: 60)], config: legacyConfig)
        // Only user-1's fetch succeeds, so the retry for user-2 cannot cache anything either way.
        setup.api.fetchNearbyGeofencesClosure = { _, _, completion in
            if contextStore.currentUserId == "user-1" {
                contextStore.setUserId("user-2")
                completion(.success(response))
            } else {
                completion(.failure(.transport))
            }
        }

        _ = await setup.coordinator.refresh(latitude: 37.0, longitude: -122.0, anchorIsLiveFix: true)

        #expect(setup.api.fetchNearbyGeofencesCallsCount >= 1)
        #expect(await cachedThresholds(fixture.storage) == [0])
    }

    @Test
    func handleMovement_givenCatalogCachedBeforeDwellWithinRefetchRadius_expectOneFetch() async throws {
        let fixture = try makeLegacyFixture()
        defer { try? FileManager.default.removeItem(at: fixture.dir) }
        let setup = makeCoordinator(storage: fixture.storage, dateUtil: fixture.dateUtil)
        let response = makeApiResponse(regions: [currentLegacyRegion(dwellThresholdSeconds: 60)], config: legacyConfig)
        setup.api.fetchNearbyGeofencesClosure = { _, _, completion in completion(.success(response)) }

        // ~200 m: inside both radii, so ordinarily a polygon wake pass with no fetch.
        let result = await setup.coordinator.handleMovement(latitude: 37.0018, longitude: -122.0, anchorIsLiveFix: true, heldFix: nil)

        #expect(result.errorOrNil == nil)
        #expect(setup.api.fetchNearbyGeofencesCallsCount == 1)
        #expect(await cachedThresholds(fixture.storage) == [60])
    }

    @Test
    func handleMovement_givenCatalogCachedBeforeDwellAndFetchFails_expectOrdinaryTierAndRetry() async throws {
        let fixture = try makeLegacyFixture()
        defer { try? FileManager.default.removeItem(at: fixture.dir) }
        let setup = makeCoordinator(storage: fixture.storage, dateUtil: fixture.dateUtil)
        setup.api.fetchNearbyGeofencesClosure = { _, _, completion in completion(.failure(.transport)) }

        let result = await setup.coordinator.handleMovement(latitude: 37.0018, longitude: -122.0, anchorIsLiveFix: true, heldFix: nil)

        #expect(result.errorOrNil == .fetchFailed(.transport))
        #expect(setup.api.fetchNearbyGeofencesCallsCount == 1)
        // The wake pass this movement would have taken keeps the registration centre; a cached
        // re-rank would have moved it to the movement.
        #expect(await fixture.storage.getLastRegistrationCenter()?.latitude == 37.0)
        #expect(await cachedThresholds(fixture.storage) == [0])

        _ = await setup.coordinator.handleMovement(latitude: 37.0018, longitude: -122.0, anchorIsLiveFix: true, heldFix: nil)
        #expect(setup.api.fetchNearbyGeofencesCallsCount == 2)
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
        let result = await setup.coordinator.refresh(latitude: 0, longitude: 0, anchorIsLiveFix: true)

        #expect(result.isSuccess)
        #expect(setup.api.fetchNearbyGeofencesCallsCount == 0)
        #expect(setup.monitor.startedRegions.isEmpty)
    }

    @Test
    func refresh_givenTimeFreshButRankingStale_expectLocalRerankNoApiCall() async {
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

        // ~2.2 km: beyond the 1 km trigger radius, within the 3 km refetch radius.
        let result = await setup.coordinator.refresh(latitude: 0.02, longitude: 0, anchorIsLiveFix: true)

        #expect(result.isSuccess)
        #expect(setup.api.fetchNearbyGeofencesCallsCount == 0)
        #expect(setup.monitor.startedRegions.contains { $0.identifier == "near" })
    }

    @Test
    func refresh_givenTimeFreshAndRankingFreshButUnregisteredCache_expectLocalRerankNoApiCall() async {
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
        // No `recordRegistration`, so nothing is registered.
        await storage.setCachedGeofences([makeRegion(id: "cached", latitude: 0, longitude: 0)])
        let setup = makeCoordinator(storage: storage, dateUtil: dateUtil)

        let result = await setup.coordinator.refresh(latitude: 0, longitude: 0, anchorIsLiveFix: true)

        #expect(result.isSuccess)
        #expect(setup.api.fetchNearbyGeofencesCallsCount == 0)
        #expect(setup.monitor.startedRegions.contains { $0.identifier == "cached" })
    }

    @Test
    func refresh_givenTimeFreshRankingFreshAndFullyCappedOut_expectSkipNoRerank() async {
        // Capped out (trigger only, no business IDs) is not "regs lost": a fresh refresh must skip.
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
        await storage.recordRegistration(center: LocationData(latitude: 0, longitude: 0), businessIds: [])
        await storage.setCachedGeofences([makeRegion(id: "far", latitude: 1, longitude: 2)]) // ~248 km, beyond the 5 km cap
        let setup = makeCoordinator(storage: storage, dateUtil: dateUtil)

        let result = await setup.coordinator.refresh(latitude: 0, longitude: 0, anchorIsLiveFix: true)

        #expect(result.isSuccess)
        #expect(setup.api.fetchNearbyGeofencesCallsCount == 0)
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

    /// A non-live anchor can be hours old and far away; ranking around it drops the fences actually
    /// nearby.
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

    /// Control: a live anchor still refetches, so the guard above can't degrade into "never move".
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
        // Integer seconds, so the storage round-trip compares equal.
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

        let result = await setup.coordinator.refresh(latitude: 0, longitude: 0, anchorIsLiveFix: true)

        #expect(result.isSuccess)
        #expect(setup.api.fetchNearbyGeofencesCallsCount == 0)
    }

    @Test
    func refresh_givenNoLastSync_expectApiCalled() async {
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

    /// Built via `JSONDecoder`: the memberwise init can't express "one arrived, none survived".
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

    /// Polygon fields without a shape are malformed, not an unsupported shape.
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

    /// Read fine, so not a failure: failing would freeze the old fences behind a refresh that never
    /// succeeds.
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

        // A geofence-free area, not a stop signal: the trigger stays armed so a later EXIT refetches.
        #expect(setup.monitor.startedRegions.map(\.identifier) == [GeofenceConstants.movementTriggerIdentifier])
    }

    @Test
    func refresh_givenEmptyServerResponseButKillSwitch_expectNothingRegistered() async {
        // `maxBusinessGeofences == 0` is the kill switch: nothing registers, not even the trigger.
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
        // Wait for the first call to reach the API so the second deterministically hits the gate.
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
        // Order matters: `recordSync` before `setCachedGeofences` plus a kill in between leaves a fresh
        // sync over a stale cache, which the freshness gate never refetches.
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

    /// Bootstrap persists what this returns, so an oversized polygon here would get membership with
    /// no OS wake.
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
        // After an empty response this is the only path that re-arms the trigger; refresh skips a
        // fresh empty cache.
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
        // The caller persists this as the ranking-staleness reference, so it must match what the OS
        // got.
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
        // A failed pass leaves the trigger on the circle just exited, where no further EXIT can fire.
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

        #expect(result.errorOrNil == .fetchFailed(.transport))
        #expect(setup.api.fetchNearbyGeofencesCallsCount == 1)
        let movementTrigger = setup.monitor.startedRegions.last { $0.identifier == GeofenceConstants.movementTriggerIdentifier }
        #expect(movementTrigger?.center == newLocation)
        #expect(movementTrigger?.radius == config.localRefreshTriggerRadius)
        // The fetch anchor stays put, so the next EXIT retries remotely.
        #expect(await storage.getLastSync()?.location == fetchAnchor)
    }

    @Test
    func handleMovement_givenRemoteFetchFailsUnderKillSwitch_expectTeardownNotRearm() async {
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

    // MARK: - Config-persisted hook

    @Test
    func handleMovement_givenTheRemoteTierPersistsAConfig_expectTheHookFired() async {
        let storage = makeStorage()
        let api = GeofenceApiServiceMock()
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            completion(.success(makeApiResponse(
                regions: [makeRegion(id: "g1", latitude: 0, longitude: 0)],
                config: .fallback
            )))
        }
        let setup = makeCoordinator(api: api, storage: storage)
        let fired = Synchronized<Int>(0)
        setup.coordinator.setOnConfigPersisted { fired.mutating { $0 += 1 } }

        // No prior sync means no anchor, which is what selects the remote tier.
        _ = await setup.coordinator.handleMovement(latitude: 1.0, longitude: 2.0, anchorIsLiveFix: true)

        #expect(fired.wrappedValue == 1)
        #expect(await storage.getCachedConfig() != nil)
    }

    /// The negative: pins the config WRITE, not just "a remote refresh ran".
    @Test
    func handleMovement_givenTheRemoteTierReturnsNoConfig_expectTheHookNotFired() async {
        let storage = makeStorage()
        let api = GeofenceApiServiceMock()
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            completion(.success(makeApiResponse(
                regions: [makeRegion(id: "g1", latitude: 0, longitude: 0)],
                config: nil
            )))
        }
        let setup = makeCoordinator(api: api, storage: storage)
        let fired = Synchronized<Int>(0)
        setup.coordinator.setOnConfigPersisted { fired.mutating { $0 += 1 } }

        _ = await setup.coordinator.handleMovement(latitude: 1.0, longitude: 2.0, anchorIsLiveFix: true)

        #expect(fired.wrappedValue == 0)
    }

    // MARK: unchanged-set fast path (crossing absorption)

    /// An initial remote refresh registers `regions`: the steady state re-ranks run against.
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
        // Re-registering re-seeds the OS's assumed state and absorbs an undelivered crossing, so
        // business regions are left alone. The wake pass must not walk the ranking anchor, or
        // re-ranking never comes due.
        let region = makeRegion(id: "g1", latitude: 0.5, longitude: 0.5)
        let storage = makeStorage()
        let setup = await makeRegisteredSetup(regions: [region], config: diffConfig, storage: storage)

        // ~111 m: inside the re-rank radius → polygon wake pass, same registered set.
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

    /// A non-live refresh anchors on the STORED registration centre, where a boundary-sized trigger
    /// may be a circle the device is already outside. Only a live fix gets the tight radius.
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
        // End-to-end: the trigger the OS is given must shrink, not just the helper's value.
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
        // Stopping and re-adding a carry-over region discards any crossing the OS detected but
        // hasn't delivered.
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
        // The OS clamps to `maximumMonitoringRadius`; comparing unclamped would re-register every pass.
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
        // Still owned in-process, but the OS dropped it: the diff must not trust ownership alone.
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
        // Held by the OS from a previous launch, never adopted: only the sweep against live OS
        // state sees it.
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
        // Cold launch: adoption seeds persisted geometry synchronously, so a sync before the re-arm
        // drains must read the region as unchanged.
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
        // CLMonitor ignores an add over a live identifier, so a reshape the OS still holds on its
        // old circle needs an explicit removal first.
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
        // Storage and OS match, but this process owns nothing yet, so everything must re-register.
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
        // Identical payload: business regions are left alone, but the trigger and both anchors
        // still walk.
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
        // Elsewhere, so a trigger re-armed here can only come from the replay.
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

    /// Taking the gate and recording a deferral must share one critical section. Asserted as an
    /// invariant, since the race window is microseconds wide.
    @Test
    func acquireGateOrDefer_givenAFreeGate_expectItIsTakenAndAnyQueuedMovementSuperseded() async {
        let setup = await makeRegisteredSetup(regions: [], config: diffConfig, storage: makeStorage())
        // Seeded, not nil: from nil the assertion below holds even with the clear outside the
        // critical section.
        setup.coordinator.deferredMovement.wrappedValue = GeofenceSyncCoordinatorImpl.DeferredMovement(
            latitude: 9, longitude: 9, anchorIsLiveFix: true,
            sequence: setup.coordinator.nextMovementSequence(), heldFix: nil
        )
        // From the allocator: a literal equal to the next minted number can't tell carrying from
        // minting.
        let replay = setup.coordinator.nextMovementSequence()

        let taken = setup.coordinator.acquireGateOrDefer(
            latitude: 1, longitude: 2, anchorIsLiveFix: true,
            replaySequence: replay, heldFix: nil
        )

        // The replay's OWN sequence: a freshly minted one would outrank a newer queued movement.
        #expect(taken == .taken(sequence: replay))
        #expect(setup.coordinator.deferredMovement.wrappedValue?.latitude == nil)
        setup.coordinator.releaseGate()
    }

    @Test
    func acquireGateOrDefer_givenAHeldGate_expectTheMovementIsRecorded() async {
        let setup = await makeRegisteredSetup(regions: [], config: diffConfig, storage: makeStorage())
        #expect(setup.coordinator.acquireGate())

        // From the allocator: `makeRegisteredSetup` has already spent a sequence.
        let taken = setup.coordinator.acquireGateOrDefer(
            latitude: 3, longitude: 4, anchorIsLiveFix: false,
            replaySequence: setup.coordinator.nextMovementSequence(), heldFix: nil
        )

        #expect(taken == .deferred)
        #expect(setup.coordinator.deferredMovement.wrappedValue?.latitude == 3)
        #expect(setup.coordinator.deferredMovement.wrappedValue?.anchorIsLiveFix == false)
        setup.coordinator.releaseGate()
    }

    @Test
    func handleMovement_givenANewerMovementRanFirst_expectTheStaleDeferralDropped() async {
        let storage = makeStorage()
        let setup = await makeRegisteredSetup(regions: [], config: diffConfig, storage: storage)

        setup.coordinator.deferredMovement.wrappedValue = GeofenceSyncCoordinatorImpl.DeferredMovement(
            latitude: 0, longitude: 0, anchorIsLiveFix: true, sequence: 1, heldFix: nil
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

    /// The gate frees and the queue clears BEFORE the replay task starts, so a newer movement can
    /// re-centre first.
    @Test
    func drainDeferredMovement_givenANewerMovementAlreadyRan_expectTheReplayDiscarded() async {
        let setup = await makeRegisteredSetup(regions: [], config: diffConfig, storage: makeStorage())
        let stale = GeofenceSyncCoordinatorImpl.DeferredMovement(
            latitude: 0, longitude: 0, anchorIsLiveFix: true, sequence: 1, heldFix: nil
        )

        let newer = LocationData(latitude: 0, longitude: 0.05)
        _ = await setup.coordinator.handleMovement(
            latitude: newer.latitude, longitude: newer.longitude, anchorIsLiveFix: true
        )
        // Stands in for a copy a drain already took off the queue, which the winner's clear can't
        // reach.
        setup.coordinator.deferredMovement.wrappedValue = stale
        setup.coordinator.drainDeferredMovement(userChanged: false)
        try? await Task.sleep(nanoseconds: 300000000)

        let triggerStarts = setup.monitor.startedRegions.filter { $0.identifier == GeofenceConstants.movementTriggerIdentifier }
        #expect(triggerStarts.last?.center == newer)
    }

    /// `makeCoordinator`, not `makeRegisteredSetup`: a registration's trailing drain can clear the
    /// seeded deferral.
    @Test
    func acquireGateOrDefer_givenANewerMovementAlreadyApplied_expectOvertaken() {
        let setup = makeCoordinator(storage: makeStorage())
        setup.coordinator.noteMovementApplied(5)

        let outcome = setup.coordinator.acquireGateOrDefer(
            latitude: 1, longitude: 2, anchorIsLiveFix: true,
            replaySequence: 3, heldFix: nil
        )

        #expect(outcome == .overtaken)
        // Refused outright, not queued: a drain would only replay it into the same refusal.
        #expect(setup.coordinator.deferredMovement.wrappedValue == nil)
    }

    /// Driven through the allocator so the ordering is one production can produce.
    @Test
    func acquireGateOrDefer_givenAFreshArrivalAfterAnAppliedPass_expectItIsTaken() {
        let setup = makeCoordinator(storage: makeStorage())
        setup.coordinator.noteMovementApplied(setup.coordinator.nextMovementSequence())

        let replay = setup.coordinator.nextMovementSequence()
        let outcome = setup.coordinator.acquireGateOrDefer(
            latitude: 1, longitude: 2, anchorIsLiveFix: true,
            replaySequence: replay, heldFix: nil
        )

        #expect(outcome == .taken(sequence: replay))
        setup.coordinator.releaseGate()
    }

    /// A replay keeps its ORIGINAL sequence, so it can lose the gate after a newer movement has queued.
    @Test
    func acquireGateOrDefer_givenAQueuedNewerMovement_expectAnOlderReplayDoesNotReplaceIt() {
        let setup = makeCoordinator(storage: makeStorage())
        #expect(setup.coordinator.acquireGate())
        setup.coordinator.deferredMovement.wrappedValue = GeofenceSyncCoordinatorImpl.DeferredMovement(
            latitude: 0, longitude: 0.05, anchorIsLiveFix: true, sequence: 2, heldFix: nil
        )

        let outcome = setup.coordinator.acquireGateOrDefer(
            latitude: 0, longitude: 0, anchorIsLiveFix: true,
            replaySequence: 1, heldFix: nil
        )

        #expect(outcome == .deferred)
        #expect(setup.coordinator.deferredMovement.wrappedValue?.sequence == 2)
        #expect(setup.coordinator.deferredMovement.wrappedValue?.longitude == 0.05)
        setup.coordinator.releaseGate()
    }

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

    /// A replay can take a briefly free gate while a NEWER arrival is queued behind it.
    @Test
    func acquireGateOrDefer_givenAQueuedNewerMovement_expectAFreeGateDoesNotClearIt() {
        let setup = makeCoordinator(storage: makeStorage())
        // Allocated in arrival order, so the replay really is the older of the two.
        let replay = setup.coordinator.nextMovementSequence()
        let queued = setup.coordinator.nextMovementSequence()
        setup.coordinator.deferredMovement.wrappedValue = GeofenceSyncCoordinatorImpl.DeferredMovement(
            latitude: 0, longitude: 0.05, anchorIsLiveFix: true, sequence: queued, heldFix: nil
        )

        let outcome = setup.coordinator.acquireGateOrDefer(
            latitude: 0, longitude: 0, anchorIsLiveFix: true,
            replaySequence: replay, heldFix: nil
        )

        #expect(outcome == .taken(sequence: replay))
        #expect(setup.coordinator.deferredMovement.wrappedValue?.sequence == queued)
        setup.coordinator.releaseGate()
    }

    @Test
    func acquireGateOrDefer_givenAQueuedOlderMovement_expectAFreeGateClearsIt() {
        let setup = makeCoordinator(storage: makeStorage())
        setup.coordinator.deferredMovement.wrappedValue = GeofenceSyncCoordinatorImpl.DeferredMovement(
            latitude: 0, longitude: 0, anchorIsLiveFix: true, sequence: 1, heldFix: nil
        )

        let outcome = setup.coordinator.acquireGateOrDefer(
            latitude: 0, longitude: 0.05, anchorIsLiveFix: true,
            replaySequence: 2, heldFix: nil
        )

        #expect(outcome == .taken(sequence: 2))
        #expect(setup.coordinator.deferredMovement.wrappedValue == nil)
        setup.coordinator.releaseGate()
    }

    /// A failed remote refresh re-arms from cache before failing, so it must still claim the re-centre.
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

    /// Discard and release must be one step, or a movement queues between them and outlives the reset.
    @Test
    func discardDeferredAndReleaseGate_expectTheQueueClearedAndTheGateFree() {
        let setup = makeCoordinator(storage: makeStorage())
        #expect(setup.coordinator.acquireGate())
        setup.coordinator.deferredMovement.wrappedValue = GeofenceSyncCoordinatorImpl.DeferredMovement(
            latitude: 0, longitude: 0.01, anchorIsLiveFix: true, sequence: 1, heldFix: nil
        )

        setup.coordinator.discardDeferredAndReleaseGate()

        #expect(setup.coordinator.deferredMovement.wrappedValue == nil)
        // Free, not merely flagged: the next movement takes it instead of queueing behind it.
        let next = setup.coordinator.acquireGateOrDefer(
            latitude: 0, longitude: 0.1, anchorIsLiveFix: true,
            replaySequence: 2, heldFix: nil
        )
        #expect(next == .taken(sequence: 2))
        setup.coordinator.releaseGate()
    }

    @Test
    func reset_givenAQueuedMovement_expectItDiscardedAndTheGateFree() async {
        let storage = makeStorage()
        let setup = makeCoordinator(storage: storage, contextStore: makeContextStore(userId: nil))
        setup.coordinator.deferredMovement.wrappedValue = GeofenceSyncCoordinatorImpl.DeferredMovement(
            latitude: 0, longitude: 0.01, anchorIsLiveFix: true, sequence: 1, heldFix: nil
        )

        _ = await setup.coordinator.reset()

        #expect(setup.coordinator.deferredMovement.wrappedValue == nil)
        #expect(setup.coordinator.acquireGate())
        setup.coordinator.releaseGate()
    }

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

    /// A refresh superseded by a user change returns success WITHOUT registering anything.
    @Test
    func refresh_givenTheUserChangedMidFetch_expectNoReCentreRecorded() async {
        let contextStore = makeContextStore(userId: "user-1")
        let api = GeofenceApiServiceMock()
        let arrived = AsyncSignal()
        let suspendUntil = AsyncSignal()
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            Task {
                await arrived.fire()
                await suspendUntil.wait()
                completion(.success(makeApiResponse(regions: [], config: diffConfig)))
            }
        }
        let setup = makeCoordinator(api: api, storage: makeStorage(), contextStore: contextStore)

        async let refreshResult = setup.coordinator.refresh(latitude: 0, longitude: 0, anchorIsLiveFix: true)
        await arrived.wait()
        contextStore.setUserId("user-2")
        await suspendUntil.fire()
        _ = await refreshResult

        #expect(setup.coordinator.appliedMovementSequence.wrappedValue == 0)
    }

    /// The kill switch reports success but plants no trigger.
    @Test
    func refresh_givenGeofencingKillSwitched_expectNoReCentreRecorded() async {
        let killSwitched = GeofenceConfig(
            localRefreshTriggerRadius: 1000, remoteFetchRefreshTriggerRadius: 5000,
            remoteFetchRefreshExpiry: 3600, duplicateEventsExpiry: 3600,
            maxBusinessGeofences: 0, maxMonitoringDistance: GeofenceConstants.noMonitoringDistanceCap
        )
        let api = GeofenceApiServiceMock()
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            completion(.success(makeApiResponse(regions: [], config: killSwitched)))
        }
        let setup = makeCoordinator(api: api, storage: makeStorage())

        _ = await setup.coordinator.refresh(latitude: 0, longitude: 0, anchorIsLiveFix: true)

        #expect(setup.monitor.startedRegions.isEmpty)
        #expect(setup.coordinator.appliedMovementSequence.wrappedValue == 0)
    }

    /// The OS drops a region for blocked permission or invalid coordinates, and the pass still
    /// succeeds.
    @Test
    func refresh_givenTheOsDroppedTheTrigger_expectNoReCentreRecorded() async {
        let monitor = MockGeofenceRegionMonitor()
        monitor.rejectedIdentifiers = [GeofenceConstants.movementTriggerIdentifier]
        let api = GeofenceApiServiceMock()
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            completion(.success(makeApiResponse(regions: [], config: diffConfig)))
        }
        let setup = makeCoordinator(api: api, storage: makeStorage(), monitor: monitor)

        _ = await setup.coordinator.refresh(latitude: 0, longitude: 0, anchorIsLiveFix: true)

        #expect(!setup.monitor.monitoredRegionIdentifiers.contains(GeofenceConstants.movementTriggerIdentifier))
        #expect(setup.coordinator.appliedMovementSequence.wrappedValue == 0)
    }

    @Test
    func applyCachedRegistration_givenTheOsDroppedTheTrigger_expectNoReCentreRecorded() {
        let monitor = MockGeofenceRegionMonitor()
        monitor.rejectedIdentifiers = [GeofenceConstants.movementTriggerIdentifier]
        let setup = makeCoordinator(storage: makeStorage(), monitor: monitor)

        _ = setup.coordinator.applyCachedRegistration(
            cachedRegions: [sampleRegion()],
            anchor: LocationData(latitude: 0, longitude: 0),
            config: .fallback,
            userId: "user-1"
        )

        #expect(setup.coordinator.appliedMovementSequence.wrappedValue == 0)
    }

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
            sequence: setup.coordinator.nextMovementSequence(), heldFix: nil
        )

        _ = await setup.coordinator.refresh(latitude: 0, longitude: 0.05, anchorIsLiveFix: true)
        setup.coordinator.deferredMovement.wrappedValue = stale

        let outcome = setup.coordinator.acquireGateOrDefer(
            latitude: stale.latitude, longitude: stale.longitude,
            anchorIsLiveFix: stale.anchorIsLiveFix, replaySequence: stale.sequence, heldFix: nil
        )

        #expect(outcome == .overtaken)
    }

    /// Allocating after acquiring lets a movement in the gap take the LOWER sequence and be retired
    /// as overtaken.
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
        #expect(!setup.coordinator.acquireGate())
        setup.coordinator.releaseGate()
    }

    /// Reachable here: the restore's gate window spans the OS registration, so a mid-registration
    /// movement can be placed exactly.
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

    /// Can't fail on a split acquire/allocate (adjacent sync statements); the restore test above
    /// discriminates.
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
        // Read from the captured sequence: the refresh's release drains the queue.
        #expect(deferredSequence > setup.coordinator.appliedMovementSequence.wrappedValue)
    }

    @Test
    func acquireGateOrDefer_givenAFreshMovementAfterAnApplied_expectItIsNeverOvertaken() {
        let setup = makeCoordinator(storage: makeStorage())
        guard case .taken(let earlier) = setup.coordinator.acquireGateOrDefer(
            latitude: 0, longitude: 0, anchorIsLiveFix: true, replaySequence: nil, heldFix: nil
        ) else {
            Issue.record("expected the free gate to be taken")
            return
        }
        setup.coordinator.noteMovementApplied(earlier)
        setup.coordinator.releaseGate()

        let outcome = setup.coordinator.acquireGateOrDefer(
            latitude: 0, longitude: 0.05, anchorIsLiveFix: true, replaySequence: nil, heldFix: nil
        )

        guard case .taken(let fresh) = outcome else {
            Issue.record("a fresh movement must never be overtaken, got \(outcome)")
            return
        }
        #expect(fresh > earlier)
        setup.coordinator.releaseGate()
    }

    @Test
    func acquireGateOrDefer_givenAReplayOlderThanTheApplied_expectOvertaken() {
        let setup = makeCoordinator(storage: makeStorage())
        let old = setup.coordinator.nextMovementSequence()
        setup.coordinator.noteMovementApplied(setup.coordinator.nextMovementSequence())

        let outcome = setup.coordinator.acquireGateOrDefer(
            latitude: 0, longitude: 0, anchorIsLiveFix: true, replaySequence: old, heldFix: nil
        )

        #expect(outcome == .overtaken)
    }

    // MARK: - Teardown ordering

    /// Clear BEFORE the OS stop, so a polygon pass resuming in between can't emit an enter for a
    /// torn-down fence. Asserted as an order: the clear is `async` and the stop `@MainActor`, so
    /// both land on one timeline.
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

    /// Same ordering via `cleanupIfUserChanged`, the other teardown site.
    @Test
    func handleMovement_givenUserChangedMidFlight_expectStateClearedBeforeTheOsStop() async {
        let recorder = TeardownOrderRecorder()
        let backing = makeStorage()
        let contextStore = makeContextStore(userId: "user-1")
        // Flipped inside the freshness read, so the pass finds a different user at its gated exit.
        let spy = SpyGeofenceSyncStorage(
            underlying: backing,
            onGetLastSync: { contextStore.setUserId("user-2") },
            onClearUserScopedState: { recorder.record("clear") }
        )
        let monitor = MockGeofenceRegionMonitor()
        monitor.onStopAll = { recorder.record("stop") }
        // Without a completion closure the API mock never completes and the suite hangs.
        let api = GeofenceApiServiceMock()
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            completion(.success(makeApiResponse(regions: [], config: diffConfig)))
        }
        let setup = makeCoordinator(api: api, storage: spy, monitor: monitor, contextStore: contextStore)

        _ = await setup.coordinator.handleMovement(latitude: 0, longitude: 0.001, anchorIsLiveFix: true)

        #expect(recorder.recorded == ["clear", "stop"])
    }

    /// Why clearing first fails closed: after it, the create guard refuses a belief for an
    /// unmonitored fence.
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
        // Pinned separately: a regression giving handleMovement its own gate would still pass the
        // forward test.
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

    /// A clamped circle no longer contains its polygon, so its exit would be false: the polygon is
    /// dropped. The circle alongside is the control that the drop is selective.
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
        // The polygon is nearer, so without the pre-ranking drop it would take the single slot.
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

    /// `evaluateAllPolygons` reads the registered set: a dropped polygon there gets membership with
    /// no OS wake.
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

    /// A polygon's `radius` is its covering circle, so the circle containment check would emit a
    /// false enter. The circle in the same pass is the negative control, so the polygon's silence
    /// isn't a dead assertion.
    @Test
    func remoteRefresh_givenNewPolygonCoveringAnchorButNotContainingIt_expectNoInitialEnter() async {
        let anchor = LocationData(latitude: 0, longitude: 0)
        // Rectangle starting ~111 m north of the anchor: every vertex is inside the 400 m covering
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

    /// The emit is fire-and-forget, so callers poll via `awaitEmits`.
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

    /// Yields a few extra times after `count` so an unwanted extra emit surfaces before the caller
    /// asserts.
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
        let emitter = await runRemoteRefresh(regions: [makeRegion(id: "g1", latitude: 1.0, longitude: 2.0)], anchor: anchor, previousIds: [])
        await awaitEmits(emitter, count: 1)
        #expect(emitter.calls.wrappedValue.map(\.geofenceId) == ["g1"])
        #expect(emitter.calls.wrappedValue.first?.transition == .enter)
    }

    @Test
    func refresh_givenMixOfNewGeofences_expectOnlyContainingEnterTypeEmitted() async {
        let anchor = LocationData(latitude: 1.0, longitude: 2.0)
        // g2 is ~222 m away, g3 exit-only; awaiting g1 proves the loop ran, so their absence is real.
        let g2 = makeRegion(id: "g2", latitude: 1.002, longitude: 2.0)
        let g3 = Geofence(id: "g3", latitude: 1.0, longitude: 2.0, radius: 100, name: "g3", transitionTypes: [.exit], lastUpdated: Date(timeIntervalSince1970: 1700000000))
        let emitter = await runRemoteRefresh(regions: [makeRegion(id: "g1", latitude: 1.0, longitude: 2.0), g2, g3], anchor: anchor, previousIds: [])
        await awaitEmits(emitter, count: 1)
        #expect(emitter.calls.wrappedValue.map(\.geofenceId) == ["g1"])
    }

    @Test
    func refresh_givenNewExitDwellCircleInside_expectVisitObservedWithoutEnterEvent() async {
        let anchor = LocationData(latitude: 1.0, longitude: 2.0)
        let storage = makeStorage()
        let contextStore = makeContextStore()
        let emitter = TransitionEmitterSpy()
        let dwellCoordinator = GeofenceDwellCoordinator(
            storage: storage,
            transitionEmitter: emitter,
            contextStore: contextStore,
            logger: LoggerMock(),
            freshFixProvider: { nil }
        )
        let dateUtil = DateUtilStub()
        await storage.recordSync(
            timestamp: dateUtil.givenNow.addingTimeInterval(-25 * 60 * 60),
            location: LocationData(latitude: 0, longitude: 0)
        )
        let region = Geofence(
            id: "exit-only",
            latitude: anchor.latitude,
            longitude: anchor.longitude,
            radius: 100,
            name: "Exit only",
            transitionTypes: [.exit],
            lastUpdated: Date(timeIntervalSince1970: 1),
            dwellThresholdSeconds: 60
        )
        let api = GeofenceApiServiceMock()
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            completion(.success(makeApiResponse(regions: [region])))
        }
        let setup = makeCoordinator(
            api: api,
            storage: storage,
            contextStore: contextStore,
            emitter: emitter,
            dwellCoordinator: dwellCoordinator,
            dateUtil: dateUtil
        )

        _ = await setup.coordinator.refresh(
            latitude: anchor.latitude,
            longitude: anchor.longitude,
            anchorIsLiveFix: true
        )
        // Bounded on the write, not a yield count: the visit is recorded on a task of its own.
        for _ in 0 ..< 200 where await storage.getDwellVisit(geofenceId: region.id) == nil {
            try? await Task.sleep(nanoseconds: 10000000)
        }

        #expect(emitter.calls.wrappedValue.isEmpty)
        let visit = await storage.getDwellVisit(geofenceId: region.id)
        #expect(visit != nil)
        // Registered around a device already inside: discovery, not an entry a dwell may report,
        // and the anchor proves no presence until a fresh fix does.
        #expect(visit?.entryObserved == false && visit?.awaitsPresenceProof == true)
    }

    /// The refresh records a widened edge before registering and keeps the record through the
    /// refresh that drops the fence, so a callback queued at the drop is still recognised.
    @Test
    func remoteRefresh_givenExitDwellCircleDropped_expectWidenedEnterStillKnownThroughTheDrop() async {
        let anchor = LocationData(latitude: 1.0, longitude: 2.0)
        let storage = makeStorage()
        let dateUtil = DateUtilStub()
        let exitOnly = Geofence(
            id: "exit-only", latitude: 1.0, longitude: 2.0, radius: 100, name: "exit-only",
            transitionTypes: [.exit], lastUpdated: Date(timeIntervalSince1970: 1700000000),
            dwellThresholdSeconds: 60
        )
        let served = Synchronized<[Geofence]>([exitOnly, makeRegion(id: "configured", latitude: 1.0, longitude: 2.0)])
        let api = GeofenceApiServiceMock()
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            completion(.success(makeApiResponse(regions: served.wrappedValue)))
        }
        let setup = makeCoordinator(api: api, storage: storage, dateUtil: dateUtil)
        let refreshRemotely = {
            await storage.recordSync(
                timestamp: dateUtil.givenNow.addingTimeInterval(-25 * 60 * 60),
                location: LocationData(latitude: 0, longitude: 0)
            )
            _ = await setup.coordinator.refresh(latitude: anchor.latitude, longitude: anchor.longitude, anchorIsLiveFix: true)
        }

        await refreshRemotely()
        let registered = setup.monitor.monitoredRegionIdentifiers
        #expect(registered.contains("exit-only"))
        served.wrappedValue = []
        await refreshRemotely()

        #expect(await storage.transitionTarget(id: "exit-only") == .uncached(unconfigured: [.enter]))
        #expect(await storage.transitionTarget(id: "configured") == .uncached(unconfigured: []))
    }

    /// The synthetic ENTER's send can stall (offline, a backlog flush). Its visit must not wait
    /// behind it, or a real EXIT in that window finds nothing to close and the write lands after.
    @Test
    func refresh_givenInitialEnterSendStalls_expectVisitRecordedWhileItIsInFlight() async {
        let anchor = LocationData(latitude: 1.0, longitude: 2.0)
        let storage = makeStorage()
        let contextStore = makeContextStore()
        let emitter = StallingEnterEmitter()
        let dwellCoordinator = GeofenceDwellCoordinator(
            storage: storage,
            transitionEmitter: emitter,
            contextStore: contextStore,
            logger: LoggerMock(),
            freshFixProvider: { nil }
        )
        let dateUtil = DateUtilStub()
        await storage.recordSync(
            timestamp: dateUtil.givenNow.addingTimeInterval(-25 * 60 * 60),
            location: LocationData(latitude: 0, longitude: 0)
        )
        let region = Geofence(
            id: "enter-exit",
            latitude: anchor.latitude,
            longitude: anchor.longitude,
            radius: 100,
            name: "Enter and exit",
            transitionTypes: [.enter, .exit],
            lastUpdated: Date(timeIntervalSince1970: 1),
            dwellThresholdSeconds: 60
        )
        let coordinator = makeStallingEnterCoordinator(
            serving: region,
            emitter: emitter,
            dwellCoordinator: dwellCoordinator,
            dateUtil: dateUtil
        )

        _ = await coordinator.refresh(
            latitude: anchor.latitude,
            longitude: anchor.longitude,
            anchorIsLiveFix: true
        )
        for _ in 0 ..< 1000 {
            if await emitter.entersReceived == 1, await storage.getDwellVisit(geofenceId: region.id) != nil { break }
            await Task.yield()
        }

        #expect(await emitter.entersReceived == 1)
        #expect(await emitter.isStalled)
        // Within a millisecond, not equal: the visit's date round-trips through JSON.
        let enteredAt = await storage.getDwellVisit(geofenceId: region.id)?.enteredAt
        #expect(abs(enteredAt?.timeIntervalSince(dateUtil.givenNow) ?? .infinity) < 0.001)
        await emitter.release()
    }

    /// A fence the SDK stops monitoring gets no EXIT. Its visit ends with the registration, so
    /// the ENTER synthesized when a later re-rank registers it again cannot adopt a stay that
    /// spans the time nobody watched. A fence that stays registered keeps its visit.
    @Test
    func registerWithOs_givenDwellFenceUnregistered_expectOnlyItsVisitEnded() async {
        let storage = makeStorage()
        let contextStore = makeContextStore()
        let dwellCoordinator = GeofenceDwellCoordinator(
            storage: storage, transitionEmitter: TransitionEmitterSpy(), contextStore: contextStore,
            logger: LoggerMock(), freshFixProvider: { nil }
        )
        let fences = ["dropped", "kept"].map { id in
            Geofence(
                id: id, latitude: 1.0, longitude: 2.0, radius: 100, name: id,
                transitionTypes: [.enter, .exit], lastUpdated: Date(timeIntervalSince1970: 1),
                dwellThresholdSeconds: 600
            )
        }
        await storage.setCachedGeofences(fences)
        for fence in fences {
            let visit = GeofenceDwellVisit(
                visitId: "visit-\(fence.id)", enteredAt: Date(), geometryRevision: fence.dwellRevision,
                userId: "user-1", emitted: false, timing: .recorded()
            )
            #expect(await storage.saveDwellVisit(visit, geofenceId: fence.id))
        }
        let setup = makeCoordinator(storage: storage, contextStore: contextStore, dwellCoordinator: dwellCoordinator)
        let register = { (regions: [Geofence]) in
            setup.coordinator.registerWithOsSync(
                businessRegions: regions,
                movementTriggerLocation: LocationData(latitude: 1.0, longitude: 2.0),
                movementTriggerRadius: 500,
                registerMovementTrigger: true
            )
        }
        register(fences)

        register([fences[1]])
        for _ in 0 ..< 200 where await storage.getDwellVisit(geofenceId: "dropped") != nil {
            await Task.yield()
        }

        #expect(await storage.getDwellVisit(geofenceId: "dropped") == nil)
        #expect(await storage.getDwellVisit(geofenceId: "kept")?.visitId == "visit-kept")
    }

    /// The post-refresh polygon pass runs on the resolver the coordinator was given. Read from
    /// `DIGraphShared.shared` instead, a replay drive built the production resolver — and with it a
    /// production dwell coordinator — mid-drive and ran the pass against the process-wide graph.
    @Test
    func refresh_expectPostRefreshPolygonPassUsesTheInjectedResolver() async {
        let storage = makeStorage()
        let contextStore = makeContextStore()
        let emitter = TransitionEmitterSpy()
        let resolver = PolygonMembershipResolver(
            storage: storage, transitionEmitter: emitter, logger: LoggerMock(), contextStore: contextStore,
            fixResolver: MovementFixResolver(logger: LoggerMock()), notificationCenter: NotificationCenter()
        )
        let requested = Synchronized<Int>(0)
        let api = GeofenceApiServiceMock()
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            completion(.success(makeApiResponse(regions: [makeRegion(id: "g1", latitude: 1.0, longitude: 2.0)])))
        }
        let dateUtil = DateUtilStub()
        await storage.recordSync(
            timestamp: dateUtil.givenNow.addingTimeInterval(-25 * 60 * 60), location: LocationData(latitude: 0, longitude: 0)
        )
        let coordinator = GeofenceSyncCoordinatorImpl(
            apiService: api, storage: storage, monitor: MockGeofenceRegionMonitor(), contextStore: contextStore,
            transitionEmitter: emitter,
            polygonResolver: {
                requested.mutating { $0 += 1 }
                return resolver
            },
            dateUtil: dateUtil, logger: LoggerMock()
        )

        _ = await coordinator.refresh(latitude: 1.0, longitude: 2.0, anchorIsLiveFix: true)

        #expect(await settleOnMain(timeout: 5) { requested.wrappedValue >= 1 })
    }

    /// `makeCoordinator` is typed to `TransitionEmitterSpy`; this wires the stalling emitter instead.
    /// Storage and identity come from `dwellCoordinator`, so all three share one store.
    private func makeStallingEnterCoordinator(
        serving region: Geofence,
        emitter: StallingEnterEmitter,
        dwellCoordinator: GeofenceDwellCoordinator,
        dateUtil: DateUtilStub
    ) -> GeofenceSyncCoordinatorImpl {
        let api = GeofenceApiServiceMock()
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            completion(.success(makeApiResponse(regions: [region])))
        }
        return GeofenceSyncCoordinatorImpl(
            apiService: api,
            storage: dwellCoordinator.storage,
            monitor: MockGeofenceRegionMonitor(),
            contextStore: dwellCoordinator.contextStore,
            transitionEmitter: emitter,
            dwellCoordinator: dwellCoordinator,
            dateUtil: dateUtil,
            logger: LoggerMock()
        )
    }

    @Test
    func refresh_givenNewAndAlreadyRegisteredInside_expectOnlyNewEmitted() async {
        let anchor = LocationData(latitude: 1.0, longitude: 2.0)
        // Both inside; `gOld` is already registered, so only `gNew` is new.
        let regions = [makeRegion(id: "gOld", latitude: 1.0, longitude: 2.0), makeRegion(id: "gNew", latitude: 1.0, longitude: 2.0)]
        let emitter = await runRemoteRefresh(regions: regions, anchor: anchor, previousIds: ["gOld"])
        await awaitEmits(emitter, count: 1)
        #expect(emitter.calls.wrappedValue.map(\.geofenceId) == ["gNew"])
    }

    @Test
    func localRefresh_givenNewGeofenceInside_expectInitialEnterEmitted() async {
        // Recent sync plus a cached region but no registration routes to a local re-rank.
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

        // Non-vacuous: the "device inside" test proves this setup emits without the rejection.
        await awaitEmits(setup.emitter, count: 0)
        #expect(setup.emitter.calls.wrappedValue.isEmpty)
    }

    @Test
    func handleMovement_givenRegisteredRegionReshapedThenRejected_expectNoLongerReportedRegistered() async {
        // A failed re-registration must drop the claim, or `emitInitialEnters` can enter an
        // unmonitored fence.
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
        #expect(!setup.monitor.osMonitoredRegions.contains("g1"))
        #expect(setup.monitor.osGeometry(for: "g1") == nil)
    }

    @Test
    func refresh_givenDeviceInsideConfiguredRadiusButOutsideOsCap_expectNoInitialEnter() async {
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

        await awaitEmits(emitter, count: 1)
        #expect(emitter.calls.wrappedValue.count == 1)
    }

    @Test
    func refresh_givenSignOutDuringRegisterPersist_expectStaleStateUndone() async {
        // After the post-fetch user check, where the sign-out's reset() is dropped on the held gate.
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
        #expect(setup.monitor.stopAllCallCount == 1)
        #expect(setup.monitor.monitoredRegionIdentifiers.isEmpty)
        #expect(await backing.getRegisteredBusinessIds().isEmpty)
        #expect(await backing.getLastSync() == nil)
        #expect(setup.emitter.calls.wrappedValue.isEmpty)
    }

    @Test
    func refresh_givenSignOutBeforeFetchFailure_expectStaleStateUndone() async {
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
        #expect(setup.monitor.stopAllCallCount == 1)
        #expect(await storage.getRegisteredBusinessIds().isEmpty)
        #expect(await storage.getLastSync() == nil)
    }

    @Test
    func refresh_givenSignOutDuringFreshnessSkip_expectStaleStateUndone() async {
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
        // B's refresh is dropped on the held gate and the exit cleanup stops everything; only the
        // retry recovers.
        let contextStore = makeContextStore(userId: "user-1")
        let storage = makeStorage()
        let api = GeofenceApiServiceMock()
        let fetchCount = Synchronized<Int>(0)
        api.fetchNearbyGeofencesClosure = { _, _, completion in
            let call = fetchCount.mutating { count -> Int in
                count += 1
                return count
            }
            // Flip to user-2 mid-flight so the post-fetch check supersedes user-1.
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

/// `@unchecked Sendable`: writes and reads are sequenced by the fetch-started signal.
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

private actor SpyGeofenceSyncStorage: GeofenceSyncStorage {
    enum Operation: Sendable, Equatable {
        case getCachedConfig
        case getCachedGeofences
        case getLastSync
        case getLastRegistrationCenter
        case getRegisteredBusinessIds
        case cachedCatalogPredatesDwell
        case setCachedGeofences
        case setCachedConfig
        case recordSync
        case recordRegistration
        case recordRegistrationIntent
        case clearUserScopedState
    }

    private let underlying: GeofenceStorage
    private(set) var operations: [Operation] = []
    /// Runs at the start of `setCachedGeofences`, the first write after the post-fetch user check.
    private let onSetCachedGeofences: (@Sendable () -> Void)?
    /// Runs at the start of `getLastSync`, inside the freshness decision.
    private let onGetLastSync: (@Sendable () -> Void)?
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

    func recordRegistrationIntent(for geofences: [Geofence], pruningToCache: Bool) async {
        operations.append(.recordRegistrationIntent)
        await underlying.recordRegistrationIntent(for: geofences, pruningToCache: pruningToCache)
    }

    func getRegisteredBusinessIds() async -> Set<String> {
        operations.append(.getRegisteredBusinessIds)
        return await underlying.getRegisteredBusinessIds()
    }

    func cachedCatalogPredatesDwell() async -> Bool {
        operations.append(.cachedCatalogPredatesDwell)
        return await underlying.cachedCatalogPredatesDwell()
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

private final class TransitionEmitterSpy: GeofenceTransitionEmitting, @unchecked Sendable {
    struct Emit: Equatable, Sendable {
        let geofenceId: String
        let transition: GeofenceTransition
        let occurredAt: Date
    }

    let calls = Synchronized<[Emit]>([])
    /// Called after each emit with its 0-based index.
    var onEmit: (@Sendable (Int) -> Void)?

    func trackTransition(geofenceId: String, transition: GeofenceTransition, occurredAt: Date) async {
        let index = calls.mutating { calls -> Int in
            calls.append(Emit(geofenceId: geofenceId, transition: transition, occurredAt: occurredAt))
            return calls.count - 1
        }
        onEmit?(index)
    }

    func trackDwell(
        geofenceId: String, occurredAt: Date, context: GeofenceDwellContext, expectedUserId: String?
    ) async -> Bool {
        await trackTransition(geofenceId: geofenceId, transition: .dwell, occurredAt: occurredAt)
        return true
    }

    func trackExit(geofenceId: String, occurredAt: Date, expectedUserId: String?) async {
        await trackTransition(geofenceId: geofenceId, transition: .exit, occurredAt: occurredAt)
    }
}

/// Holds every ENTER inside the tracker, a send that has not come back, until released.
private actor StallingEnterEmitter: GeofenceTransitionEmitting {
    private var released = false
    private var stalledSends: [CheckedContinuation<Void, Never>] = []
    private(set) var entersReceived = 0

    var isStalled: Bool {
        !stalledSends.isEmpty
    }

    func trackTransition(geofenceId: String, transition: GeofenceTransition, occurredAt: Date) async {
        guard transition == .enter else { return }
        entersReceived += 1
        guard !released else { return }
        await withCheckedContinuation { stalledSends.append($0) }
    }

    func release() {
        released = true
        stalledSends.forEach { $0.resume() }
        stalledSends.removeAll()
    }

    func trackDwell(
        geofenceId: String, occurredAt: Date, context: GeofenceDwellContext, expectedUserId: String?
    ) async -> Bool {
        true
    }

    func trackExit(geofenceId: String, occurredAt: Date, expectedUserId: String?) async {}
}

// MARK: - Async signal helper

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
