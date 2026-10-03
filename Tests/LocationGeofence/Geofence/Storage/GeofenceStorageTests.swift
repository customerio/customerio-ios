@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation
import SharedTests
import Testing

@Suite("GeofenceStorage")
struct GeofenceStorageTests {
    private func makeTempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func makeStorage(directory: URL) -> GeofenceStorage {
        GeofenceStorage(fileManager: .default, directoryURL: directory)
    }

    // MARK: - Cooldown operations

    @Test
    func getEventCooldowns_givenEmpty_expectEmptyDictionary() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let cooldowns = await storage.getEventCooldowns()
        #expect(cooldowns.isEmpty)
    }

    @Test
    func recordEventCooldown_givenKey_expectPersisted() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let timestamp = Date(timeIntervalSince1970: 1700000000)
        await storage.recordEventCooldown(key: "geo_1:enter", timestamp: timestamp)
        let cooldowns = await storage.getEventCooldowns()
        #expect(cooldowns["geo_1:enter"] == timestamp)
    }

    @Test
    func recordEventCooldown_givenMultipleKeys_expectAllPersisted() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let t1 = Date(timeIntervalSince1970: 1700000000)
        let t2 = Date(timeIntervalSince1970: 1700001000)
        await storage.recordEventCooldown(key: "geo_1:enter", timestamp: t1)
        await storage.recordEventCooldown(key: "geo_1:exit", timestamp: t2)
        let cooldowns = await storage.getEventCooldowns()
        #expect(cooldowns.count == 2)
        #expect(cooldowns["geo_1:enter"] == t1)
        #expect(cooldowns["geo_1:exit"] == t2)
    }

    @Test
    func purgeExpiredCooldowns_givenSomeExpired_expectOnlyExpiredRemoved() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let interval: TimeInterval = 3600
        let now = Date(timeIntervalSince1970: 1700000000)
        let staleTimestamp = now.addingTimeInterval(-interval - 1)
        let freshTimestamp = now.addingTimeInterval(-1)
        await storage.recordEventCooldown(key: "geo_stale:enter", timestamp: staleTimestamp)
        await storage.recordEventCooldown(key: "geo_fresh:enter", timestamp: freshTimestamp)

        await storage.purgeExpiredCooldowns(now: now, interval: interval)

        let cooldowns = await storage.getEventCooldowns()
        #expect(cooldowns["geo_stale:enter"] == nil)
        #expect(cooldowns["geo_fresh:enter"] == freshTimestamp)
    }

    @Test
    func purgeExpiredCooldowns_givenNoneExpired_expectAllRetained() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let now = Date(timeIntervalSince1970: 1700000000)
        await storage.recordEventCooldown(key: "geo_1:enter", timestamp: now)

        await storage.purgeExpiredCooldowns(now: now, interval: 3600)

        let cooldowns = await storage.getEventCooldowns()
        #expect(cooldowns["geo_1:enter"] == now)
    }

    // MARK: - Atomic cooldown acquisition

    @Test
    func tryAcquireCooldown_givenNoExistingEntry_expectAcquiredAndRecorded() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let now = Date(timeIntervalSince1970: 1700000000)

        let remaining = await storage.tryAcquireCooldown(key: "geo_1:enter", now: now, interval: 3600)

        #expect(remaining == nil)
        let cooldowns = await storage.getEventCooldowns()
        #expect(cooldowns["geo_1:enter"] == now)
    }

    @Test
    func tryAcquireCooldown_givenEntryWithinInterval_expectNotAcquiredAndTimestampUnchanged() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let firstAttempt = Date(timeIntervalSince1970: 1700000000)
        let secondAttempt = firstAttempt.addingTimeInterval(1800)

        _ = await storage.tryAcquireCooldown(key: "geo_1:enter", now: firstAttempt, interval: 3600)
        let remaining = await storage.tryAcquireCooldown(key: "geo_1:enter", now: secondAttempt, interval: 3600)

        #expect(remaining == 1800)
        let cooldowns = await storage.getEventCooldowns()
        #expect(cooldowns["geo_1:enter"] == firstAttempt)
    }

    @Test
    func tryAcquireCooldown_givenEntryAtIntervalBoundary_expectAcquiredAndTimestampReplaced() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let firstAttempt = Date(timeIntervalSince1970: 1700000000)
        let secondAttempt = firstAttempt.addingTimeInterval(3600)

        _ = await storage.tryAcquireCooldown(key: "geo_1:enter", now: firstAttempt, interval: 3600)
        let remaining = await storage.tryAcquireCooldown(key: "geo_1:enter", now: secondAttempt, interval: 3600)

        #expect(remaining == nil)
        let cooldowns = await storage.getEventCooldowns()
        #expect(cooldowns["geo_1:enter"] == secondAttempt)
    }

    @Test
    func tryAcquireCooldown_givenDifferentKey_expectIndependentAcquisition() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let now = Date(timeIntervalSince1970: 1700000000)

        _ = await storage.tryAcquireCooldown(key: "geo_1:enter", now: now, interval: 3600)
        let remaining = await storage.tryAcquireCooldown(key: "geo_2:enter", now: now, interval: 3600)

        #expect(remaining == nil)
    }

    @Test
    func clearEventCooldowns_givenCooldowns_expectAllRemoved() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        await storage.recordEventCooldown(key: "geo_1:enter", timestamp: Date())
        await storage.recordEventCooldown(key: "geo_2:exit", timestamp: Date())
        await storage.clearEventCooldowns()
        let cooldowns = await storage.getEventCooldowns()
        #expect(cooldowns.isEmpty)
    }

    // MARK: - Persistence across instances

    @Test
    func recordEventCooldown_givenNewStorageInstance_expectLoadsFromDisk() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let storage1 = makeStorage(directory: dir)
        let timestamp = Date(timeIntervalSince1970: 1700000000)
        await storage1.recordEventCooldown(key: "geo_1:enter", timestamp: timestamp)

        let storage2 = makeStorage(directory: dir)
        let cooldowns = await storage2.getEventCooldowns()
        #expect(cooldowns["geo_1:enter"] == timestamp)
    }

    @Test
    func recordEventCooldown_givenSecondCall_expectOverwritesOnDisk() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let first = Date(timeIntervalSince1970: 1)
        let second = Date(timeIntervalSince1970: 2)
        await storage.recordEventCooldown(key: "geo_1:enter", timestamp: first)
        await storage.recordEventCooldown(key: "geo_1:enter", timestamp: second)
        let cooldowns = await storage.getEventCooldowns()
        #expect(cooldowns["geo_1:enter"] == second)
    }

    // MARK: - Cached geofences

    private func makeGeofence(id: String, radius: Double = 100, transitions: Set<GeofenceTransition> = [.enter]) -> Geofence {
        Geofence(id: id, latitude: 1.0, longitude: 2.0, radius: radius, name: id, transitionTypes: transitions, lastUpdated: Date(timeIntervalSince1970: 1700000000))
    }

    @Test
    func getCachedGeofences_givenNoState_expectEmpty() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let cached = await storage.getCachedGeofences()
        #expect(cached.isEmpty)
    }

    @Test
    func setCachedGeofences_thenGet_expectRoundTrip() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let geofences = [
            makeGeofence(id: "g1", radius: 100, transitions: [.enter]),
            makeGeofence(id: "g2", radius: 200, transitions: [.enter, .exit])
        ]
        await storage.setCachedGeofences(geofences)
        let cached = await storage.getCachedGeofences()
        #expect(cached == geofences)
    }

    @Test
    func setCachedGeofences_givenGeosetIds_expectRoundTrip() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let geofence = Geofence(
            id: "g1", latitude: 1.0, longitude: 2.0, radius: 100, name: "g1",
            transitionTypes: [.enter], lastUpdated: Date(timeIntervalSince1970: 1700000000),
            geosetIds: ["set_y", "set_z"]
        )
        await storage.setCachedGeofences([geofence])
        let cached = await storage.getCachedGeofences()
        #expect(cached.first?.geosetIds == ["set_y", "set_z"])
    }

    @Test
    func decode_givenGeofenceCachedByPreGeosetVersion_expectEmptyGeosetIds() throws {
        let legacyJson = """
        {"id":"g1","latitude":1,"longitude":2,"radius":100,"name":"g1","transitionTypes":["enter"],"lastUpdated":1700000000}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let geofence = try decoder.decode(Geofence.self, from: Data(legacyJson.utf8))

        #expect(geofence.geosetIds == [])
    }

    @Test
    func setCachedGeofences_givenSecondCall_expectOverwrites() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        await storage.setCachedGeofences([makeGeofence(id: "g1")])
        await storage.setCachedGeofences([makeGeofence(id: "g2"), makeGeofence(id: "g3")])
        let cached = await storage.getCachedGeofences()
        #expect(cached.map(\.id) == ["g2", "g3"])
    }

    @Test
    func setCachedGeofences_givenNewStorageInstance_expectLoadsFromDisk() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let storage1 = makeStorage(directory: dir)
        await storage1.setCachedGeofences([makeGeofence(id: "g1")])

        let storage2 = makeStorage(directory: dir)
        let cached = await storage2.getCachedGeofences()
        #expect(cached.map(\.id) == ["g1"])
    }

    // MARK: - Cached config

    @Test
    func getCachedConfig_givenNoState_expectNil() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let config = await storage.getCachedConfig()
        #expect(config == nil)
    }

    @Test
    func setCachedConfig_thenGet_expectRoundTrip() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let config = GeofenceConfig(
            localRefreshTriggerRadius: 750,
            remoteFetchRefreshTriggerRadius: 4000,
            remoteFetchRefreshExpiry: 12 * 60 * 60,
            duplicateEventsExpiry: 30 * 60,
            maxBusinessGeofences: 10,
            maxMonitoringDistance: 50000
        )
        await storage.setCachedConfig(config)
        let cached = await storage.getCachedConfig()
        #expect(cached == config)
    }

    @Test
    func setCachedConfig_givenNewStorageInstance_expectLoadsFromDisk() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = GeofenceConfig.fallback

        let storage1 = makeStorage(directory: dir)
        await storage1.setCachedConfig(config)

        let storage2 = makeStorage(directory: dir)
        let cached = await storage2.getCachedConfig()
        #expect(cached == config)
    }

    @Test
    func setCachedConfig_doesNotClearGeofencesOrCooldowns() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let timestamp = Date(timeIntervalSince1970: 1700000000)
        await storage.recordEventCooldown(key: "geo_1:enter", timestamp: timestamp)
        await storage.setCachedGeofences([makeGeofence(id: "g1")])

        await storage.setCachedConfig(.fallback)

        let cooldowns = await storage.getEventCooldowns()
        #expect(cooldowns["geo_1:enter"] == timestamp)
        let geofences = await storage.getCachedGeofences()
        #expect(geofences.map(\.id) == ["g1"])
    }

    @Test
    func setCachedConfig_givenSecondCall_expectOverwrites() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        await storage.setCachedConfig(.fallback)
        let updated = GeofenceConfig(
            localRefreshTriggerRadius: 500,
            remoteFetchRefreshTriggerRadius: 2000,
            remoteFetchRefreshExpiry: 60,
            duplicateEventsExpiry: 30,
            maxBusinessGeofences: 5,
            maxMonitoringDistance: GeofenceConstants.noMonitoringDistanceCap
        )
        await storage.setCachedConfig(updated)
        let cached = await storage.getCachedConfig()
        #expect(cached == updated)
    }

    // MARK: - Last sync

    @Test
    func getLastSync_givenNoState_expectNil() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let record = await storage.getLastSync()
        #expect(record == nil)
    }

    @Test
    func recordSync_thenGet_expectRoundTrip() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let timestamp = Date(timeIntervalSince1970: 1700000000)
        let location = LocationData(latitude: 37.7749, longitude: -122.4194)

        await storage.recordSync(timestamp: timestamp, location: location)
        let record = await storage.getLastSync()

        #expect(record?.timestamp == timestamp)
        #expect(record?.location == location)
    }

    @Test
    func recordSync_givenSecondCall_expectOverwritesBothFields() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let firstTime = Date(timeIntervalSince1970: 1700000000)
        let firstLocation = LocationData(latitude: 37.7749, longitude: -122.4194)
        let secondTime = Date(timeIntervalSince1970: 1700003600)
        let secondLocation = LocationData(latitude: 40.7128, longitude: -74.0060)

        await storage.recordSync(timestamp: firstTime, location: firstLocation)
        await storage.recordSync(timestamp: secondTime, location: secondLocation)
        let record = await storage.getLastSync()

        #expect(record?.timestamp == secondTime)
        #expect(record?.location == secondLocation)
    }

    @Test
    func recordSync_givenNewStorageInstance_expectLoadsFromDisk() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let timestamp = Date(timeIntervalSince1970: 1700000000)
        let location = LocationData(latitude: 1.0, longitude: 2.0)

        let storage1 = makeStorage(directory: dir)
        await storage1.recordSync(timestamp: timestamp, location: location)

        let storage2 = makeStorage(directory: dir)
        let record = await storage2.getLastSync()

        #expect(record?.timestamp == timestamp)
        #expect(record?.location == location)
    }

    @Test
    func getLastSync_givenOnlyTimestampOnDisk_expectNilFromDefensiveGuard() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var partial = GeofenceState()
        partial.lastServerSyncTimestamp = Date(timeIntervalSince1970: 1700000000)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try? encoder.encode(partial).write(to: dir.appendingPathComponent("geofenceState.json"))

        let storage = makeStorage(directory: dir)
        let record = await storage.getLastSync()

        #expect(record == nil)
    }

    @Test
    func getLastSync_givenOnlyLocationOnDisk_expectNilFromDefensiveGuard() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var partial = GeofenceState()
        partial.lastServerSyncLocation = LocationData(latitude: 1.0, longitude: 2.0)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try? encoder.encode(partial).write(to: dir.appendingPathComponent("geofenceState.json"))

        let storage = makeStorage(directory: dir)
        let record = await storage.getLastSync()

        #expect(record == nil)
    }

    @Test
    func recordSync_doesNotClearOtherState() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let cooldownTime = Date(timeIntervalSince1970: 1700000000)
        await storage.recordEventCooldown(key: "geo_1:enter", timestamp: cooldownTime)
        await storage.setCachedGeofences([makeGeofence(id: "g1")])
        await storage.setCachedConfig(.fallback)

        await storage.recordSync(
            timestamp: Date(timeIntervalSince1970: 1700003600),
            location: LocationData(latitude: 1.0, longitude: 2.0)
        )

        let cooldowns = await storage.getEventCooldowns()
        #expect(cooldowns["geo_1:enter"] == cooldownTime)
        let geofences = await storage.getCachedGeofences()
        #expect(geofences.map(\.id) == ["g1"])
        let config = await storage.getCachedConfig()
        #expect(config == .fallback)
    }

    @Test
    func setCachedGeofences_doesNotClearCooldowns() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let timestamp = Date(timeIntervalSince1970: 1700000000)
        await storage.recordEventCooldown(key: "geo_1:enter", timestamp: timestamp)

        await storage.setCachedGeofences([makeGeofence(id: "g1")])

        let cooldowns = await storage.getEventCooldowns()
        #expect(cooldowns["geo_1:enter"] == timestamp)
    }

    // MARK: - Concurrent safety

    @Test
    func recordRegistration_thenGet_expectRoundTrip() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let center = LocationData(latitude: 37.7749, longitude: -122.4194)

        await storage.recordRegistration(center: center, businessIds: ["g1", "g2"])

        #expect(await storage.getLastRegistrationCenter() == center)
        #expect(await storage.getRegisteredBusinessIds() == ["g1", "g2"])
    }

    @Test
    func recordRegistration_givenEvictedFence_expectDwellVisitPruned() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let geofence = Geofence(
            id: "g1",
            latitude: 1,
            longitude: 2,
            radius: 100,
            name: "g1",
            transitionTypes: [.exit],
            lastUpdated: Date(timeIntervalSince1970: 1),
            dwellThresholdSeconds: 60
        )
        await storage.setCachedGeofences([geofence])
        #expect(await storage.saveDwellVisit(
            GeofenceDwellVisit(
                visitId: "visit-1",
                enteredAt: Date(timeIntervalSince1970: 100),
                geometryRevision: geofence.dwellRevision,
                userId: "user-1",
                emitted: false, timing: nil
            ),
            geofenceId: geofence.id
        ))

        await storage.recordRegistration(
            center: LocationData(latitude: 1, longitude: 2),
            businessIds: []
        )

        #expect(await storage.getDwellVisit(geofenceId: geofence.id) == nil)
    }

    /// A visit from before `entryObserved` also predates identity provenance: it still decodes,
    /// keeps its id, reports no entry, and, being unqualified, awaits its next fresh proof.
    @Test
    func getDwellVisit_givenVisitPersistedBeforeEntryObserved_expectDecodedConservatively() async throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let legacyState = """
        {"dwellVisits":{"g1":{"visitId":"visit-1","enteredAt":100,"geometryRevision":"rev","userId":"user-1","emitted":false}}}
        """
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(legacyState.utf8).write(to: dir.appendingPathComponent("geofenceState.json"))
        let storage = makeStorage(directory: dir)

        let visit = await storage.getDwellVisit(geofenceId: "g1")

        #expect(visit?.visitId == "visit-1")
        #expect(visit?.entryObserved == false)
        #expect(visit?.awaitsPresenceProof == true)
        #expect(visit?.identityVersion == nil)
    }

    @Test
    func saveDwellVisit_givenUnobservedEntry_expectPersisted() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let geofence = Geofence(
            id: "g1", latitude: 1, longitude: 2, radius: 100, name: "g1",
            transitionTypes: [.exit], lastUpdated: Date(timeIntervalSince1970: 1),
            dwellThresholdSeconds: 60
        )
        await storage.setCachedGeofences([geofence])
        #expect(await storage.saveDwellVisit(
            GeofenceDwellVisit(
                visitId: "visit-1",
                enteredAt: Date(timeIntervalSince1970: 100),
                geometryRevision: geofence.dwellRevision,
                userId: "user-1",
                emitted: false,
                entryObserved: false,
                timing: nil
            ),
            geofenceId: geofence.id
        ))

        #expect(await makeStorage(directory: dir).getDwellVisit(geofenceId: geofence.id)?.entryObserved == false)
    }

    /// A fence with nothing to track a visit for is refused rather than given one it never clears.
    @Test
    func saveDwellVisit_givenEnterOnlyFenceWithoutDwellThreshold_expectRefused() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let geofence = Geofence(
            id: "g1", latitude: 1, longitude: 2, radius: 100, name: "g1",
            transitionTypes: [.enter], lastUpdated: Date(timeIntervalSince1970: 1)
        )
        await storage.setCachedGeofences([geofence])

        let saved = await storage.saveDwellVisit(
            GeofenceDwellVisit(
                visitId: "visit-1",
                enteredAt: Date(timeIntervalSince1970: 100),
                geometryRevision: geofence.dwellRevision,
                userId: "user-1",
                emitted: false, timing: nil
            ),
            geofenceId: geofence.id
        )

        #expect(!saved)
        #expect(await storage.getDwellVisit(geofenceId: geofence.id) == nil)
    }

    /// Nothing upstream dedupes fence ids, and building the retention lookup with
    /// `uniqueKeysWithValues` trapped on the first payload that listed one twice — on every sync.
    /// The first occurrence decides, as every `first(where:)` read of the same cache does.
    @Test
    func setCachedGeofences_givenDuplicateIds_expectNoCrashAndFirstOccurrenceDecidesRetention() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let first = Geofence(
            id: "g1", latitude: 1, longitude: 2, radius: 100, name: "g1",
            transitionTypes: [.exit], lastUpdated: Date(timeIntervalSince1970: 1),
            dwellThresholdSeconds: 60
        )
        let reshaped = Geofence(
            id: "g1", latitude: 1, longitude: 2, radius: 250, name: "g1",
            transitionTypes: [.exit], lastUpdated: Date(timeIntervalSince1970: 2),
            dwellThresholdSeconds: 60
        )
        await storage.setCachedGeofences([first])
        #expect(await storage.saveDwellVisit(
            GeofenceDwellVisit(
                visitId: "visit-1",
                enteredAt: Date(timeIntervalSince1970: 100),
                geometryRevision: first.dwellRevision,
                userId: "user-1",
                emitted: false, timing: nil
            ),
            geofenceId: first.id
        ))

        await storage.setCachedGeofences([first, reshaped])
        #expect(await storage.getDwellVisit(geofenceId: "g1")?.visitId == "visit-1")

        await storage.setCachedGeofences([reshaped, first])
        #expect(await storage.getDwellVisit(geofenceId: "g1") == nil)
    }

    @Test
    func clearUserScopedState_expectCooldownsLastSyncAndRegistrationCleared_workspaceCachePreserved() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        _ = await storage.tryAcquireCooldown(key: "g1:enter", now: Date(timeIntervalSince1970: 100), interval: 3600)
        let geofence = Geofence(
            id: "g1", latitude: 0, longitude: 0, radius: 100, name: "g1",
            transitionTypes: [.enter, .exit], lastUpdated: Date(timeIntervalSince1970: 0),
            dwellThresholdSeconds: 60
        )
        await storage.setCachedGeofences([geofence])
        #expect(await storage.saveDwellVisit(
            GeofenceDwellVisit(
                visitId: "visit-1",
                enteredAt: Date(timeIntervalSince1970: 50),
                geometryRevision: geofence.dwellRevision,
                userId: "user-1",
                emitted: false, timing: nil
            ),
            geofenceId: geofence.id
        ))
        await storage.setCachedConfig(.fallback)
        await storage.recordSync(timestamp: Date(timeIntervalSince1970: 100), location: LocationData(latitude: 1, longitude: 2))
        await storage.recordRegistration(center: LocationData(latitude: 1, longitude: 2), businessIds: ["g1"])
        await storage.recordMonitorRegistration(identifier: "g1", transitionTypes: [.enter, .exit], initialState: .enter, center: LocationData(latitude: 10, longitude: 20), radius: 100)
        await storage.recordRegistrationIntent(for: [intentFence("old-user-dwell-only", types: [], dwell: 60)], pruningToCache: false)

        await storage.clearUserScopedState()

        let cooldowns = await storage.getEventCooldowns()
        let lastSync = await storage.getLastSync()
        let regions = await storage.getCachedGeofences()
        let config = await storage.getCachedConfig()
        #expect(cooldowns.isEmpty)
        #expect(lastSync == nil)
        #expect(await storage.getLastRegistrationCenter() == nil)
        #expect(await storage.getRegisteredBusinessIds().isEmpty)
        #expect(await storage.getDwellVisit(geofenceId: geofence.id) == nil)
        #expect(await storage.transitionTarget(id: "old-user-dwell-only") == .uncached(unconfigured: []))
        #expect(await storage.recordMonitorEvent(.enter, forIdentifier: "g1") == .suppressedNoBaseline)
        #expect(regions.map(\.id) == ["g1"])
        #expect(config != nil)
    }

    @Test
    func concurrentOperations_expectNoCrash() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)

        await withTaskGroup(of: Void.self) { group in
            for i in 0 ..< 20 {
                group.addTask {
                    for j in 0 ..< 10 {
                        switch (i + j) % 3 {
                        case 0:
                            await storage.recordEventCooldown(key: "geo_\(i):enter", timestamp: Date())
                        case 1:
                            _ = await storage.getEventCooldowns()
                        case 2:
                            await storage.purgeExpiredCooldowns(now: Date(), interval: 3600)
                        default:
                            break
                        }
                    }
                }
            }
        }
        _ = await storage.getEventCooldowns()
    }

    // MARK: - Monitor region records (CLMonitor dedup + delivery filter)

    @Test
    func recordMonitorEvent_givenNoRegistration_expectBaselineEstablishedNoDelivery() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let outcome = await storage.recordMonitorEvent(.exit, forIdentifier: "geo_1")
        #expect(outcome == .suppressedNoBaseline)
        #expect(await storage.recordMonitorEvent(.exit, forIdentifier: "geo_1") == .suppressedNoChange)
    }

    @Test
    func recordMonitorRegistration_givenRegisteredInside_expectNoSpuriousEnter() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        await storage.recordMonitorRegistration(identifier: "geo_1", transitionTypes: [.enter, .exit], initialState: .enter, center: LocationData(latitude: 10, longitude: 20), radius: 100)
        #expect(await storage.recordMonitorEvent(.enter, forIdentifier: "geo_1") == .suppressedNoChange)
        #expect(await storage.recordMonitorEvent(.exit, forIdentifier: "geo_1") == .deliver)
    }

    @Test
    func recordMonitorEvent_givenRegisteredOutsideThenEnter_expectDeliver() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        await storage.recordMonitorRegistration(identifier: "geo_1", transitionTypes: [.enter, .exit], initialState: .exit, center: LocationData(latitude: 10, longitude: 20), radius: 100)
        #expect(await storage.recordMonitorEvent(.enter, forIdentifier: "geo_1") == .deliver)
    }

    @Test
    func recordMonitorEvent_givenReplayedInitialState_expectNoChange() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        await storage.recordMonitorRegistration(identifier: "geo_1", transitionTypes: [.enter, .exit], initialState: .exit, center: LocationData(latitude: 10, longitude: 20), radius: 100)
        #expect(await storage.recordMonitorEvent(.exit, forIdentifier: "geo_1") == .suppressedNoChange)
    }

    @Test
    func recordMonitorEvent_givenDeliveredThenReplayed_expectNoChange() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        await storage.recordMonitorRegistration(identifier: "geo_1", transitionTypes: [.enter, .exit], initialState: .exit, center: LocationData(latitude: 10, longitude: 20), radius: 100)
        #expect(await storage.recordMonitorEvent(.enter, forIdentifier: "geo_1") == .deliver)
        #expect(await storage.recordMonitorEvent(.enter, forIdentifier: "geo_1") == .suppressedNoChange)
    }

    @Test
    func recordMonitorEvent_givenEvidenceOlderThanBaseline_expectSuppressedAndBaselineUntouched() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let crossingAt = Date()
        await storage.recordMonitorRegistration(identifier: "geo_1", transitionTypes: [.enter, .exit], initialState: .exit, center: LocationData(latitude: 10, longitude: 20), radius: 100)
        // A real crossing lands while a heal whose fix predates it is queued; the heal must lose.
        #expect(await storage.recordMonitorEvent(.enter, forIdentifier: "geo_1", now: crossingAt) == .deliver)
        let outcome = await storage.recordMonitorEvent(
            .exit,
            forIdentifier: "geo_1",
            onlyIfBaselinePredates: crossingAt.addingTimeInterval(-20)
        )
        #expect(outcome == .suppressedNewerBaseline)
        #expect(await storage.recordMonitorEvent(.exit, forIdentifier: "geo_1") == .deliver)
    }

    @Test
    func recordMonitorEvent_givenEvidenceNotOlderThanBaseline_expectDeliver() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let seededAt = Date()
        await storage.recordMonitorRegistration(identifier: "geo_1", transitionTypes: [.enter, .exit], initialState: .exit, center: LocationData(latitude: 10, longitude: 20), radius: 100, now: seededAt)
        // Not exact equality: the stamp round-trips disk as seconds-since-1970 and can shift by
        // nanoseconds.
        #expect(await storage.recordMonitorEvent(.enter, forIdentifier: "geo_1", onlyIfBaselinePredates: seededAt.addingTimeInterval(1)) == .deliver)
    }

    @Test
    func recordMonitorEvent_givenGuardAgainstPreStampRecord_expectDeliver() async throws {
        // Persisted before `lastStateChangedAt` existed; a nil stamp must fail open.
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let legacyState = """
        {"monitorRegionRecords":{"geo_1":{"lastState":"exit","transitionTypes":["enter","exit"],"center":{"latitude":10,"longitude":20},"radius":100}}}
        """
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(legacyState.utf8).write(to: dir.appendingPathComponent("geofenceState.json"))
        let storage = makeStorage(directory: dir)
        #expect(await storage.recordMonitorEvent(.enter, forIdentifier: "geo_1", onlyIfBaselinePredates: Date(timeIntervalSince1970: 0)) == .deliver)
    }

    // MARK: - OS event identity (`osEventDate`)

    @Test
    func recordMonitorEvent_givenSameOsEventDateTwice_expectRedelivered() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let center = LocationData(latitude: 10, longitude: 20)
        let eventAt = Date(timeIntervalSince1970: 1789215260.147529)
        await storage.recordMonitorRegistration(identifier: "geo_1", transitionTypes: [.enter, .exit], initialState: .exit, center: center, radius: 100, now: eventAt.addingTimeInterval(-600))
        #expect(await storage.recordMonitorEvent(.enter, forIdentifier: "geo_1", osEventDate: eventAt) == .deliver)
        #expect(await storage.recordMonitorEvent(.enter, forIdentifier: "geo_1", osEventDate: eventAt) == .suppressedRedelivery)
    }

    @Test
    func recordMonitorEvent_givenCopyDatedFractionallyEarlier_expectRedelivered() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let center = LocationData(latitude: 10, longitude: 20)
        let eventAt = Date(timeIntervalSince1970: 1789215260.147529)
        await storage.recordMonitorRegistration(identifier: "geo_1", transitionTypes: [.enter, .exit], initialState: .exit, center: center, radius: 100, now: eventAt.addingTimeInterval(-600))
        #expect(await storage.recordMonitorEvent(.enter, forIdentifier: "geo_1", osEventDate: eventAt) == .deliver)
        // Copies aren't always date-identical or delivered in date order.
        #expect(await storage.recordMonitorEvent(.enter, forIdentifier: "geo_1", osEventDate: eventAt.addingTimeInterval(-0.000001)) == .suppressedRedelivery)
        #expect(await storage.recordMonitorEvent(.exit, forIdentifier: "geo_1", osEventDate: eventAt.addingTimeInterval(60)) == .deliver)
    }

    @Test
    func recordMonitorEvent_givenNoChangeWithOsEventDate_expectDateRememberedForLaterCopy() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let center = LocationData(latitude: 10, longitude: 20)
        let eventAt = Date(timeIntervalSince1970: 1789215260.147529)
        await storage.recordMonitorRegistration(identifier: "geo_1", transitionTypes: [.enter, .exit], initialState: .exit, center: center, radius: 100, now: eventAt.addingTimeInterval(-600))
        #expect(await storage.recordMonitorEvent(.exit, forIdentifier: "geo_1", osEventDate: eventAt) == .suppressedNoChange)
        #expect(await storage.recordMonitorEvent(.exit, forIdentifier: "geo_1", osEventDate: eventAt) == .suppressedRedelivery)
    }

    /// The wall clock is set back an hour after an ENTER. Every stamp the record holds is then in
    /// the future, and a genuine EXIT dated on the corrected clock must not be refused as a
    /// redelivery, as predating registration, or as older than the baseline.
    @Test
    func recordMonitorTransition_givenWallClockSetBackSinceTheLastEvent_expectNewCrossingDelivered() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let clock = DateUtilStub()
        let registeredAt = Date(timeIntervalSince1970: 1789215000)
        clock.givenNow = registeredAt
        let storage = GeofenceStorage(fileManager: .default, directoryURL: dir, dateUtil: clock)
        await storage.recordMonitorRegistration(
            identifier: "geo_1", transitionTypes: [.enter, .exit], initialState: .exit,
            center: LocationData(latitude: 10, longitude: 20), radius: 100
        )
        let enteredAt = registeredAt.addingTimeInterval(60)
        clock.givenNow = enteredAt
        #expect(await storage.recordMonitorEvent(
            .enter, forIdentifier: "geo_1", onlyIfBaselinePredates: enteredAt, osEventDate: enteredAt, now: enteredAt
        ) == .deliver)

        let exitedAt = enteredAt.addingTimeInterval(600 - 3600)
        clock.givenNow = exitedAt
        #expect(await storage.recordMonitorEvent(
            .exit, forIdentifier: "geo_1", onlyIfBaselinePredates: exitedAt, osEventDate: exitedAt, now: exitedAt
        ) == .deliver)
        // Ordering resumes on the corrected clock: a copy of that EXIT is still a redelivery.
        #expect(await storage.recordMonitorEvent(
            .exit, forIdentifier: "geo_1", onlyIfBaselinePredates: exitedAt, osEventDate: exitedAt, now: exitedAt
        ) == .suppressedRedelivery)
    }

    /// A copy of an event from before the clock was set back is dated in that same future, so it
    /// is still ordered against the stamps it left behind.
    @Test
    func recordMonitorTransition_givenCopyFromBeforeTheClockWasSetBack_expectStillRedelivered() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let clock = DateUtilStub()
        let registeredAt = Date(timeIntervalSince1970: 1789215000)
        clock.givenNow = registeredAt
        let storage = GeofenceStorage(fileManager: .default, directoryURL: dir, dateUtil: clock)
        await storage.recordMonitorRegistration(
            identifier: "geo_1", transitionTypes: [.enter, .exit], initialState: .exit,
            center: LocationData(latitude: 10, longitude: 20), radius: 100
        )
        let exitedAt = registeredAt.addingTimeInterval(30)
        let enteredAt = registeredAt.addingTimeInterval(60)
        #expect(await storage.recordMonitorEvent(.enter, forIdentifier: "geo_1", osEventDate: enteredAt, now: enteredAt) == .deliver)

        clock.givenNow = enteredAt.addingTimeInterval(-3600)
        #expect(await storage.recordMonitorEvent(.exit, forIdentifier: "geo_1", osEventDate: exitedAt, now: exitedAt) == .suppressedRedelivery)
    }

    @Test
    func recordMonitorEvent_givenOsEventDatedBeforeChangedCircle_expectPredatesRegistration() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let reshapedAt = Date(timeIntervalSince1970: 1789215260.748)
        await storage.recordMonitorRegistration(identifier: "trigger", transitionTypes: [.exit], initialState: .enter, center: LocationData(latitude: 10, longitude: 20), radius: 1000, now: reshapedAt.addingTimeInterval(-3600))
        // A business circle despite the id: exited, then re-centred.
        #expect(await storage.recordMonitorEvent(.exit, forIdentifier: "trigger", osEventDate: reshapedAt.addingTimeInterval(-0.2)) == .deliver)
        await storage.recordMonitorRegistration(identifier: "trigger", transitionTypes: [.exit], initialState: .enter, center: LocationData(latitude: 10.02, longitude: 20), radius: 1000, now: reshapedAt)
        // A corrective computed against the old circle; by state alone it would read as a crossing.
        let oldExitAt = reshapedAt.addingTimeInterval(-0.042)
        #expect(await storage.recordMonitorEvent(
            .exit, forIdentifier: "trigger",
            onlyIfBaselinePredates: oldExitAt, osEventDate: oldExitAt, now: oldExitAt
        ) == .suppressedPredatesRegistration)
        #expect(await storage.recordMonitorEvent(.exit, forIdentifier: "trigger", osEventDate: reshapedAt.addingTimeInterval(300)) == .deliver)
    }

    @Test
    func recordMonitorEvent_givenMovementTriggerExitBeforeReplant_expectExemptFromPredates() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let id = GeofenceConstants.movementTriggerIdentifier
        let replantAt = Date(timeIntervalSince1970: 1789215260.748)
        await storage.recordMonitorRegistration(identifier: id, transitionTypes: [.exit], initialState: .enter, center: LocationData(latitude: 10, longitude: 20), radius: 1000, now: replantAt.addingTimeInterval(-3600))
        // Re-planted at a smaller radius, so `registeredAt` moves forward.
        await storage.recordMonitorRegistration(identifier: id, transitionTypes: [.exit], initialState: .enter, center: LocationData(latitude: 10, longitude: 20), radius: 100, now: replantAt)
        // Dated just before the re-plant: a business circle drops this, the movement trigger must not.
        let exitAt = replantAt.addingTimeInterval(-0.042)
        #expect(await storage.recordMonitorEvent(
            .exit, forIdentifier: id,
            onlyIfBaselinePredates: exitAt, osEventDate: exitAt, now: exitAt
        ) == .deliver)
        #expect(await storage.recordMonitorEvent(
            .exit, forIdentifier: id,
            onlyIfBaselinePredates: exitAt, osEventDate: exitAt, now: exitAt
        ) == .suppressedRedelivery)
        // The delayed exit belonged to the old circle, so the new circle's later exit still delivers.
        let newExitAt = replantAt.addingTimeInterval(300)
        #expect(await storage.recordMonitorEvent(
            .exit, forIdentifier: id,
            onlyIfBaselinePredates: newExitAt, osEventDate: newExitAt, now: newExitAt
        ) == .deliver)
    }

    @Test
    func recordMonitorEvent_givenHandledMovementExitBeforeReplant_expectCopySuppressed() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let id = GeofenceConstants.movementTriggerIdentifier
        let replantAt = Date(timeIntervalSince1970: 1789215260.748)
        await storage.recordMonitorRegistration(identifier: id, transitionTypes: [.exit], initialState: .enter, center: LocationData(latitude: 10, longitude: 20), radius: 1000, now: replantAt.addingTimeInterval(-3600))
        let exitAt = replantAt.addingTimeInterval(-0.2)
        #expect(await storage.recordMonitorEvent(
            .exit, forIdentifier: id,
            onlyIfBaselinePredates: exitAt, osEventDate: exitAt, now: exitAt
        ) == .deliver)
        await storage.recordMonitorRegistration(identifier: id, transitionTypes: [.exit], initialState: .enter, center: LocationData(latitude: 10, longitude: 20), radius: 100, now: replantAt)
        #expect(await storage.recordMonitorEvent(
            .exit, forIdentifier: id,
            onlyIfBaselinePredates: exitAt, osEventDate: exitAt, now: exitAt
        ) == .suppressedRedelivery)
    }

    @Test
    func recordMonitorEvent_givenMovementTriggerAlreadyOutsideAtReplant_expectOldExitStillWakes() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let id = GeofenceConstants.movementTriggerIdentifier
        let replantAt = Date(timeIntervalSince1970: 1789215260.748)
        await storage.recordMonitorRegistration(identifier: id, transitionTypes: [.exit], initialState: .enter, center: LocationData(latitude: 10, longitude: 20), radius: 1000, now: replantAt.addingTimeInterval(-3600))
        // A stale anchor can plant the trigger with the device already outside it.
        await storage.recordMonitorRegistration(identifier: id, transitionTypes: [.exit], initialState: .exit, center: LocationData(latitude: 10, longitude: 20), radius: 100, now: replantAt)
        let exitAt = replantAt.addingTimeInterval(-0.042)
        #expect(await storage.recordMonitorEvent(
            .exit, forIdentifier: id,
            onlyIfBaselinePredates: exitAt, osEventDate: exitAt, now: exitAt
        ) == .deliver)
        #expect(await storage.recordMonitorEvent(
            .exit, forIdentifier: id,
            onlyIfBaselinePredates: exitAt, osEventDate: exitAt, now: exitAt
        ) == .suppressedRedelivery)
    }

    @Test
    func recordMonitorRegistration_givenUnchangedReRegistration_expectIncarnationPreserved() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let center = LocationData(latitude: 10, longitude: 20)
        let registeredAt = Date(timeIntervalSince1970: 1789215000)
        await storage.recordMonitorRegistration(identifier: "geo_1", transitionTypes: [.enter, .exit], initialState: .exit, center: center, radius: 100, now: registeredAt)
        await storage.recordMonitorRegistration(identifier: "geo_1", transitionTypes: [.enter, .exit], initialState: .exit, center: center, radius: 100, now: registeredAt.addingTimeInterval(600))
        #expect(await storage.recordMonitorEvent(.enter, forIdentifier: "geo_1", osEventDate: registeredAt.addingTimeInterval(300)) == .deliver)
    }

    @Test
    func recordMonitorRegistration_givenForceReseed_expectNewIncarnation() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let center = LocationData(latitude: 10, longitude: 20)
        let registeredAt = Date(timeIntervalSince1970: 1789215000)
        await storage.recordMonitorRegistration(identifier: "geo_1", transitionTypes: [.enter, .exit], initialState: .exit, center: center, radius: 100, now: registeredAt)
        await storage.recordMonitorRegistration(identifier: "geo_1", transitionTypes: [.enter, .exit], initialState: .exit, center: center, radius: 100, forceReseed: true, now: registeredAt.addingTimeInterval(600))
        #expect(await storage.recordMonitorEvent(.enter, forIdentifier: "geo_1", osEventDate: registeredAt.addingTimeInterval(300)) == .suppressedPredatesRegistration)
    }

    @Test
    func recordMonitorEvent_givenLegacyRecordWithoutIdentityFields_expectDeliver() async throws {
        // Persisted before `registeredAt` / `lastEventDate` existed; nil refuses nothing.
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let legacyState = """
        {"monitorRegionRecords":{"geo_1":{"lastState":"exit","transitionTypes":["enter","exit"],"center":{"latitude":10,"longitude":20},"radius":100}}}
        """
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try legacyState.write(to: dir.appendingPathComponent("geofenceState.json"), atomically: true, encoding: .utf8)
        let storage = makeStorage(directory: dir)
        #expect(await storage.recordMonitorEvent(.enter, forIdentifier: "geo_1", osEventDate: Date(timeIntervalSince1970: 1789215260)) == .deliver)
    }

    @Test
    func recordMonitorRegistration_givenUnchangedReRegistration_expectStampPreserved() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let crossingAt = Date()
        await storage.recordMonitorRegistration(identifier: "geo_1", transitionTypes: [.enter, .exit], initialState: .exit, center: LocationData(latitude: 10, longitude: 20), radius: 100, now: crossingAt.addingTimeInterval(-60))
        #expect(await storage.recordMonitorEvent(.enter, forIdentifier: "geo_1", now: crossingAt) == .deliver)
        await storage.recordMonitorRegistration(identifier: "geo_1", transitionTypes: [.enter, .exit], initialState: .exit, center: LocationData(latitude: 10, longitude: 20), radius: 100, now: crossingAt.addingTimeInterval(30))
        #expect(await storage.recordMonitorEvent(.exit, forIdentifier: "geo_1", onlyIfBaselinePredates: crossingAt.addingTimeInterval(5)) == .deliver)
    }

    @Test
    func recordMonitorRegistration_givenChangedGeometry_expectStampReset() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let reshapedAt = Date()
        await storage.recordMonitorRegistration(identifier: "geo_1", transitionTypes: [.enter, .exit], initialState: .enter, center: LocationData(latitude: 10, longitude: 20), radius: 100, now: reshapedAt.addingTimeInterval(-60))
        await storage.recordMonitorRegistration(identifier: "geo_1", transitionTypes: [.enter, .exit], initialState: .exit, center: LocationData(latitude: 11, longitude: 20), radius: 200, now: reshapedAt)
        #expect(await storage.recordMonitorEvent(.enter, forIdentifier: "geo_1", onlyIfBaselinePredates: reshapedAt.addingTimeInterval(-5)) == .suppressedNewerBaseline)
    }

    @Test
    func recordMonitorRegistration_givenUnchangedReRegistration_expectBaselinePreserved() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        await storage.recordMonitorRegistration(identifier: "geo_1", transitionTypes: [.enter, .exit], initialState: .exit, center: LocationData(latitude: 10, longitude: 20), radius: 100)
        #expect(await storage.recordMonitorEvent(.enter, forIdentifier: "geo_1") == .deliver) // walked in
        // The reseed guess (.exit) must not override the tracked .enter.
        await storage.recordMonitorRegistration(identifier: "geo_1", transitionTypes: [.enter, .exit], initialState: .exit, center: LocationData(latitude: 10, longitude: 20), radius: 100)
        #expect(await storage.recordMonitorEvent(.enter, forIdentifier: "geo_1") == .suppressedNoChange)
    }

    @Test
    func recordMonitorRegistration_givenChangedGeometry_expectBaselineReseededToActual() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        // Inside the old circle → baseline .enter.
        await storage.recordMonitorRegistration(identifier: "geo_1", transitionTypes: [.enter, .exit], initialState: .enter, center: LocationData(latitude: 10, longitude: 20), radius: 100)
        // Same id, changed geometry; the device is now outside the new circle.
        await storage.recordMonitorRegistration(identifier: "geo_1", transitionTypes: [.enter, .exit], initialState: .exit, center: LocationData(latitude: 11, longitude: 20), radius: 200)
        #expect(await storage.recordMonitorEvent(.exit, forIdentifier: "geo_1") == .suppressedNoChange)
        #expect(await storage.recordMonitorEvent(.enter, forIdentifier: "geo_1") == .deliver)
    }

    @Test
    func clearMonitorRegionRecord_givenOsStoppedMonitoring_expectNextArrivalDelivered() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let center = LocationData(latitude: 10, longitude: 20)
        await storage.recordMonitorRegistration(identifier: "geo_1", transitionTypes: [.enter, .exit], initialState: .exit, center: center, radius: 100)
        #expect(await storage.recordMonitorEvent(.enter, forIdentifier: "geo_1") == .deliver)
        await storage.clearMonitorRegionRecord(identifier: "geo_1")
        await storage.recordMonitorRegistration(identifier: "geo_1", transitionTypes: [.enter, .exit], initialState: .exit, center: center, radius: 100)
        #expect(await storage.recordMonitorEvent(.enter, forIdentifier: "geo_1") == .deliver)
    }

    @Test
    func recordMonitorRegistration_givenForceReseedOnUnchangedGeometry_expectBaselineReset() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let center = LocationData(latitude: 10, longitude: 20)
        await storage.recordMonitorRegistration(identifier: "geo_1", transitionTypes: [.enter, .exit], initialState: .exit, center: center, radius: 100)
        #expect(await storage.recordMonitorEvent(.enter, forIdentifier: "geo_1") == .deliver)
        // A same-circle registration drained before the deferred record clear could run.
        await storage.recordMonitorRegistration(identifier: "geo_1", transitionTypes: [.enter, .exit], initialState: .exit, center: center, radius: 100, forceReseed: true)
        #expect(await storage.recordMonitorEvent(.enter, forIdentifier: "geo_1") == .deliver)
    }

    @Test
    func recordMonitorRegistration_givenUnchangedGeometryWithoutForceReseed_expectBaselinePreserved() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let center = LocationData(latitude: 10, longitude: 20)
        await storage.recordMonitorRegistration(identifier: "geo_1", transitionTypes: [.enter, .exit], initialState: .exit, center: center, radius: 100)
        #expect(await storage.recordMonitorEvent(.enter, forIdentifier: "geo_1") == .deliver)
        await storage.recordMonitorRegistration(identifier: "geo_1", transitionTypes: [.enter, .exit], initialState: .exit, center: center, radius: 100)
        #expect(await storage.recordMonitorEvent(.enter, forIdentifier: "geo_1") == .suppressedNoChange)
    }

    @Test
    func clearMonitorRegionRecord_givenOtherRegions_expectOnlyTargetDropped() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let center = LocationData(latitude: 10, longitude: 20)
        await storage.recordMonitorRegistration(identifier: "geo_1", transitionTypes: [.enter], initialState: .exit, center: center, radius: 100)
        await storage.recordMonitorRegistration(identifier: "geo_2", transitionTypes: [.enter], initialState: .exit, center: center, radius: 100)
        await storage.clearMonitorRegionRecord(identifier: "geo_1")
        #expect(await storage.getMonitorRegionRecords().keys.sorted() == ["geo_2"])
        await storage.clearMonitorRegionRecord(identifier: "absent")
        #expect(await storage.getMonitorRegionRecords().keys.sorted() == ["geo_2"])
    }

    @Test
    func recordMonitorEvent_givenUnregisteredTransitionType_expectRecordedNotDelivered() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        // Exit-only region, registered outside (baseline .exit).
        await storage.recordMonitorRegistration(identifier: "geo_1", transitionTypes: [.exit], initialState: .exit, center: LocationData(latitude: 10, longitude: 20), radius: 100)
        // The enter advances the baseline but is not delivered...
        #expect(await storage.recordMonitorEvent(.enter, forIdentifier: "geo_1") == .suppressedFilteredType)
        // ...so the following exit is recognized as a change and delivered.
        #expect(await storage.recordMonitorEvent(.exit, forIdentifier: "geo_1") == .deliver)
    }

    @Test
    func recordMonitorEvent_givenSeparateIdentifiers_expectIndependentBaselines() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        await storage.recordMonitorRegistration(identifier: "geo_1", transitionTypes: [.enter, .exit], initialState: .exit, center: LocationData(latitude: 10, longitude: 20), radius: 100)
        await storage.recordMonitorRegistration(identifier: "geo_2", transitionTypes: [.enter, .exit], initialState: .exit, center: LocationData(latitude: 10, longitude: 20), radius: 100)
        #expect(await storage.recordMonitorEvent(.enter, forIdentifier: "geo_1") == .deliver)
        #expect(await storage.recordMonitorEvent(.exit, forIdentifier: "geo_2") == .suppressedNoChange)
    }

    @Test
    func recordMonitorEvent_givenPersistedBaseline_expectSurvivesColdStart() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = makeStorage(directory: dir)
        await first.recordMonitorRegistration(identifier: "geo_1", transitionTypes: [.enter, .exit], initialState: .exit, center: LocationData(latitude: 10, longitude: 20), radius: 100)
        #expect(await first.recordMonitorEvent(.enter, forIdentifier: "geo_1") == .deliver) // walked in
        let afterRelaunch = makeStorage(directory: dir)
        #expect(await afterRelaunch.recordMonitorEvent(.enter, forIdentifier: "geo_1") == .suppressedNoChange)
        #expect(await afterRelaunch.recordMonitorEvent(.exit, forIdentifier: "geo_1") == .deliver)
    }

    @Test
    func getMonitorRegionRecords_givenRegistrationsAndEvents_expectGeometryAndBaselinesReturned() async {
        // The adopt-time re-arm rebuilds conditions from this, so it must carry the current baseline.
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        await storage.recordMonitorRegistration(identifier: "geo_1", transitionTypes: [.enter, .exit], initialState: .exit, center: LocationData(latitude: 10, longitude: 20), radius: 100)
        _ = await storage.recordMonitorEvent(.enter, forIdentifier: "geo_1") // baseline advances

        let records = await storage.getMonitorRegionRecords()

        #expect(records["geo_1"]?.center == LocationData(latitude: 10, longitude: 20))
        #expect(records["geo_1"]?.radius == 100)
        #expect(records["geo_1"]?.lastState == .enter)
    }

    // MARK: - Monitor baseline pruning

    @Test
    func recordRegistration_givenEvictedRegion_expectItsBaselineDropped() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let centre = LocationData(latitude: 10, longitude: 20)
        await storage.recordMonitorRegistration(identifier: "evicted", transitionTypes: [.enter, .exit], initialState: .enter, center: centre, radius: 500)
        await storage.recordMonitorRegistration(identifier: "kept", transitionTypes: [.enter, .exit], initialState: .exit, center: centre, radius: 500)

        await storage.recordRegistration(center: centre, businessIds: ["kept"])

        let records = await storage.getMonitorRegionRecords()
        #expect(records["evicted"] == nil)
        #expect(records["kept"] != nil)
    }

    @Test
    func recordRegistration_givenMovementTrigger_expectItsBaselineRetained() async {
        // The trigger is never in `businessIds`; pruning it would lose the baseline its exit needs.
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let centre = LocationData(latitude: 10, longitude: 20)
        await storage.recordMonitorRegistration(identifier: GeofenceConstants.movementTriggerIdentifier, transitionTypes: [.exit], initialState: .enter, center: centre, radius: 1000)

        await storage.recordRegistration(center: centre, businessIds: ["g1"])

        #expect(await storage.getMonitorRegionRecords()[GeofenceConstants.movementTriggerIdentifier] != nil)
    }

    @Test
    func revisit_givenRegionEvictedWhileInside_expectGenuineEnterStillDelivered() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let centre = LocationData(latitude: 10, longitude: 20)
        let radius: Double = 500

        await storage.recordMonitorRegistration(identifier: "F", transitionTypes: [.enter, .exit], initialState: .exit, center: centre, radius: radius)
        #expect(await storage.recordMonitorEvent(.enter, forIdentifier: "F") == .deliver)

        // Evicted while still inside — F is absent from the new registration snapshot.
        await storage.recordRegistration(center: centre, businessIds: [])

        // Much later: re-registered with an identical circle, device now outside.
        await storage.recordMonitorRegistration(identifier: "F", transitionTypes: [.enter, .exit], initialState: .exit, center: centre, radius: radius)

        #expect(await storage.recordMonitorEvent(.enter, forIdentifier: "F") == .deliver)
    }

    @Test
    func recordRegistration_givenRetainedRegion_expectBaselinePreserved() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let centre = LocationData(latitude: 10, longitude: 20)
        await storage.recordMonitorRegistration(identifier: "g1", transitionTypes: [.enter, .exit], initialState: .exit, center: centre, radius: 500)
        #expect(await storage.recordMonitorEvent(.enter, forIdentifier: "g1") == .deliver)

        await storage.recordRegistration(center: centre, businessIds: ["g1"])
        await storage.recordMonitorRegistration(identifier: "g1", transitionTypes: [.enter, .exit], initialState: .exit, center: centre, radius: 500)

        #expect(await storage.recordMonitorEvent(.enter, forIdentifier: "g1") == .suppressedNoChange)
    }

    @Test
    func diagnosticReason_expectEverySuppressionNamedAndDeliverSilent() {
        // A case wired to `nil` compiles, and the caller's `if let` swallows it. `allCases` covers
        // new cases.
        let cases = GeofenceMonitorEventOutcome.allCases
        for outcome in cases {
            if case .deliver = outcome {
                #expect(outcome.diagnosticReason == nil, "deliver is not a discard and must log nothing")
            } else {
                let reason = outcome.diagnosticReason
                #expect(reason != nil, "\(outcome) has no diagnostic token")
                // Tokens ride in a whitespace-split tail, so a space would break the parser.
                #expect(!(reason ?? " ").contains(" "), "\(outcome): token must not contain whitespace")
            }
        }
        // Distinct reasons, or two different discards read as the same thing off-device.
        let tokens = cases.compactMap(\.diagnosticReason)
        #expect(Set(tokens).count == tokens.count, "duplicate tokens: \(tokens)")
    }

    // MARK: - Re-delivered OS events

    /// Every re-delivered copy carries the original event `date`.
    private static let trigger = GeofenceConstants.movementTriggerIdentifier
    private static let eventDate = Date(timeIntervalSince1970: 1000060.107)
    private static let reseedAt = Date(timeIntervalSince1970: 1000060.238)

    private func registerTrigger(_ storage: GeofenceStorage, longitude: Double, at now: Date) async {
        await storage.recordMonitorRegistration(
            identifier: Self.trigger, transitionTypes: [.enter, .exit], initialState: .enter,
            center: LocationData(latitude: 10, longitude: longitude), radius: 1000, now: now
        )
    }

    @Test
    func recordMonitorEvent_givenCopyBeforeReseed_expectNoStateChange() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        await registerTrigger(storage, longitude: 20, at: Date(timeIntervalSince1970: 1000000))

        #expect(await storage.recordMonitorEvent(.exit, forIdentifier: Self.trigger, onlyIfBaselinePredates: Self.eventDate, now: Self.eventDate) == .deliver)
        #expect(await storage.recordMonitorEvent(.exit, forIdentifier: Self.trigger, onlyIfBaselinePredates: Self.eventDate, now: Self.eventDate) == .suppressedNoChange)
    }

    @Test
    func recordMonitorEvent_givenCopyAfterReseed_expectRefusedAsStale() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        await registerTrigger(storage, longitude: 20, at: Date(timeIntervalSince1970: 1000000))

        #expect(await storage.recordMonitorEvent(.exit, forIdentifier: Self.trigger, onlyIfBaselinePredates: Self.eventDate, now: Self.eventDate) == .deliver)
        await registerTrigger(storage, longitude: 20.01, at: Self.reseedAt)
        #expect(await storage.recordMonitorEvent(.exit, forIdentifier: Self.trigger, onlyIfBaselinePredates: Self.eventDate, now: Self.eventDate) == .suppressedNewerBaseline)
    }

    @Test
    func recordMonitorEvent_givenLaterEventAfterReseed_expectDelivered() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        await registerTrigger(storage, longitude: 20, at: Date(timeIntervalSince1970: 1000000))

        #expect(await storage.recordMonitorEvent(.exit, forIdentifier: Self.trigger, onlyIfBaselinePredates: Self.eventDate, now: Self.eventDate) == .deliver)
        await registerTrigger(storage, longitude: 20.01, at: Self.reseedAt)
        let later = Self.reseedAt.addingTimeInterval(300)
        #expect(await storage.recordMonitorEvent(.exit, forIdentifier: Self.trigger, onlyIfBaselinePredates: later, now: later) == .deliver)
    }

    // MARK: - Registration intent

    private func intentFence(
        _ id: String,
        types: Set<GeofenceTransition>,
        dwell: Int = 0,
        polygon: Bool = false
    ) -> Geofence {
        Geofence(
            id: id, latitude: 0, longitude: 0, radius: 100, name: id,
            transitionTypes: types, lastUpdated: Date(timeIntervalSince1970: 1),
            vertices: polygon ? [
                LocationData(latitude: 0, longitude: 0),
                LocationData(latitude: 0, longitude: 0.001),
                LocationData(latitude: 0.001, longitude: 0)
            ] : nil,
            dwellThresholdSeconds: dwell
        )
    }

    /// Only edges a circle is registered for beyond what the customer configured are recorded.
    @Test
    func recordRegistrationIntent_givenEachFenceShape_expectOnlyBookkeepingEdgesRecorded() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let fences = [
            intentFence("exit-only", types: [.exit]),
            intentFence("exit-dwell", types: [.exit], dwell: 60),
            intentFence("dwell-only", types: [], dwell: 60),
            intentFence("enter-dwell", types: [.enter], dwell: 60),
            intentFence("enter-exit", types: [.enter, .exit]),
            intentFence("enter-only", types: [.enter]),
            intentFence("exit-only-polygon", types: [.exit], polygon: true)
        ]

        await storage.recordRegistrationIntent(for: fences, pruningToCache: true)

        #expect(await storage.transitionTarget(id: "exit-only") == .uncached(unconfigured: []))
        #expect(await storage.transitionTarget(id: "exit-dwell") == .uncached(unconfigured: [.enter]))
        #expect(await storage.transitionTarget(id: "dwell-only") == .uncached(unconfigured: [.enter, .exit]))
        #expect(await storage.transitionTarget(id: "enter-dwell") == .uncached(unconfigured: [.exit]))
        #expect(await storage.transitionTarget(id: "enter-exit") == .uncached(unconfigured: []))
        #expect(await storage.transitionTarget(id: "enter-only") == .uncached(unconfigured: []))
        #expect(await storage.transitionTarget(id: "exit-only-polygon") == .uncached(unconfigured: []))
    }

    /// A fence's record outlives the cache write that drops it by one refresh — callbacks queued
    /// when it was unregistered — and is forgotten by the next.
    @Test
    func recordRegistrationIntent_givenFenceDropped_expectKeptThroughOneRefreshThenForgotten() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let exitDwell = intentFence("exit-dwell", types: [.exit], dwell: 60)
        await storage.recordRegistrationIntent(for: [exitDwell], pruningToCache: true)
        await storage.setCachedGeofences([exitDwell])
        #expect(await storage.transitionTarget(id: "exit-dwell") == .cached(exitDwell))

        await storage.recordRegistrationIntent(for: [], pruningToCache: true)
        await storage.setCachedGeofences([])
        #expect(await storage.transitionTarget(id: "exit-dwell") == .uncached(unconfigured: [.enter]))

        await storage.recordRegistrationIntent(for: [], pruningToCache: true)
        await storage.setCachedGeofences([])
        #expect(await storage.transitionTarget(id: "exit-dwell") == .uncached(unconfigured: []))
    }

    /// A fence reconfigured to include ENTER loses its record, so its ENTER is forwarded again.
    @Test
    func recordRegistrationIntent_givenFenceReconfiguredWithEnter_expectRecordCleared() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        await storage.recordRegistrationIntent(for: [intentFence("fence", types: [.exit], dwell: 60)], pruningToCache: false)

        await storage.recordRegistrationIntent(
            for: [intentFence("fence", types: [.enter, .exit], dwell: 60)], pruningToCache: false
        )

        #expect(await storage.transitionTarget(id: "fence") == .uncached(unconfigured: []))
    }
}
