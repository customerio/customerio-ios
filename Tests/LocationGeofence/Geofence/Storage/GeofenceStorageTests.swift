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

        let acquired = await storage.tryAcquireCooldown(key: "geo_1:enter", now: now, interval: 3600)

        #expect(acquired == true)
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
        let acquired = await storage.tryAcquireCooldown(key: "geo_1:enter", now: secondAttempt, interval: 3600)

        #expect(acquired == false)
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
        let acquired = await storage.tryAcquireCooldown(key: "geo_1:enter", now: secondAttempt, interval: 3600)

        #expect(acquired == true)
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
        let acquired = await storage.tryAcquireCooldown(key: "geo_2:enter", now: now, interval: 3600)

        #expect(acquired == true)
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
        // Geofences cached to disk before the `geosetIds` field existed must keep
        // decoding after an upgrade; a missing key means no geoset membership.
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
        // Write a state file with timestamp but no location — simulates a torn state from
        // an older client or a partial future-schema migration.
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
    func clearUserScopedState_expectCooldownsLastSyncAndRegistrationCleared_workspaceCachePreserved() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        _ = await storage.tryAcquireCooldown(key: "g1:enter", now: Date(timeIntervalSince1970: 100), interval: 3600)
        await storage.setCachedGeofences([
            Geofence(id: "g1", latitude: 0, longitude: 0, radius: 100, name: "g1", transitionTypes: [.enter], lastUpdated: Date(timeIntervalSince1970: 0))
        ])
        await storage.setCachedConfig(.fallback)
        await storage.recordSync(timestamp: Date(timeIntervalSince1970: 100), location: LocationData(latitude: 1, longitude: 2))
        await storage.recordRegistration(center: LocationData(latitude: 1, longitude: 2), businessIds: ["g1"])
        await storage.recordMonitorRegistration(identifier: "g1", transitionTypes: [.enter, .exit], initialState: .enter, center: LocationData(latitude: 10, longitude: 20), radius: 100)

        await storage.clearUserScopedState()

        let cooldowns = await storage.getEventCooldowns()
        let lastSync = await storage.getLastSync()
        let regions = await storage.getCachedGeofences()
        let config = await storage.getCachedConfig()
        #expect(cooldowns.isEmpty)
        #expect(lastSync == nil)
        // Registration is user-scoped — cleared so the next user re-registers from their own refresh.
        #expect(await storage.getLastRegistrationCenter() == nil)
        #expect(await storage.getRegisteredBusinessIds().isEmpty)
        // Monitor baseline is dropped: a post-clear event for the same id finds no record (no stale
        // baseline inherited), so it re-establishes silently instead of comparing to the old state.
        #expect(await storage.recordMonitorEvent(.enter, forIdentifier: "g1") == .suppressedNoBaseline)
        // Workspace cache is shared across users — preserved.
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
        // A condition with no registration record: first observation is baseline, not a crossing.
        let outcome = await storage.recordMonitorEvent(.exit, forIdentifier: "geo_1")
        #expect(outcome == .suppressedNoBaseline)
        // The same state replayed is now a no-change suppression.
        #expect(await storage.recordMonitorEvent(.exit, forIdentifier: "geo_1") == .suppressedNoChange)
    }

    @Test
    func recordMonitorRegistration_givenRegisteredInside_expectNoSpuriousEnter() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        // Registered while the device is INSIDE the region → baseline seeded to the actual state
        // (.enter). CLMonitor re-evaluating that same state is suppressed — the register-while-inside
        // parity fix: no spurious enter at registration (classic is silent too).
        await storage.recordMonitorRegistration(identifier: "geo_1", transitionTypes: [.enter, .exit], initialState: .enter, center: LocationData(latitude: 10, longitude: 20), radius: 100)
        #expect(await storage.recordMonitorEvent(.enter, forIdentifier: "geo_1") == .suppressedNoChange)
        // The subsequent genuine exit delivers.
        #expect(await storage.recordMonitorEvent(.exit, forIdentifier: "geo_1") == .deliver)
    }

    @Test
    func recordMonitorEvent_givenRegisteredOutsideThenEnter_expectDeliver() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        // Registered outside (baseline .exit). CLMonitor emits no initial event (assumption matched);
        // the first REAL crossing (walk in) must still deliver — the baseline isn't blank.
        await storage.recordMonitorRegistration(identifier: "geo_1", transitionTypes: [.enter, .exit], initialState: .exit, center: LocationData(latitude: 10, longitude: 20), radius: 100)
        #expect(await storage.recordMonitorEvent(.enter, forIdentifier: "geo_1") == .deliver)
    }

    @Test
    func recordMonitorEvent_givenReplayedInitialState_expectNoChange() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        await storage.recordMonitorRegistration(identifier: "geo_1", transitionTypes: [.enter, .exit], initialState: .exit, center: LocationData(latitude: 10, longitude: 20), radius: 100)
        // CLMonitor re-emitting the state we seeded at registration (relaunch/unlock replay).
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
    func recordMonitorRegistration_givenUnchangedReRegistration_expectBaselinePreserved() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        await storage.recordMonitorRegistration(identifier: "geo_1", transitionTypes: [.enter, .exit], initialState: .exit, center: LocationData(latitude: 10, longitude: 20), radius: 100)
        #expect(await storage.recordMonitorEvent(.enter, forIdentifier: "geo_1") == .deliver) // walked in
        // Sync re-registration (stop-all + start-all) with UNCHANGED geometry (same center/radius)
        // preserves the baseline, so CLMonitor re-evaluating the still-inside state is suppressed. The
        // reseed-guess passed here (.exit) must NOT override the tracked .enter.
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
        // Backend moves the geofence (same id, CHANGED center/radius). The device is now OUTSIDE the new
        // circle, so the changed-geometry registration reseeds the baseline to .exit instead of carrying
        // the stale .enter — CLMonitor re-evaluating "outside" is then suppressed, not fired as a spurious exit.
        await storage.recordMonitorRegistration(identifier: "geo_1", transitionTypes: [.enter, .exit], initialState: .exit, center: LocationData(latitude: 11, longitude: 20), radius: 200)
        #expect(await storage.recordMonitorEvent(.exit, forIdentifier: "geo_1") == .suppressedNoChange)
        // A real crossing into the new circle still delivers.
        #expect(await storage.recordMonitorEvent(.enter, forIdentifier: "geo_1") == .deliver)
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
        // geo_2 has its own baseline, untouched by geo_1's events.
        #expect(await storage.recordMonitorEvent(.exit, forIdentifier: "geo_2") == .suppressedNoChange)
    }

    @Test
    func recordMonitorEvent_givenPersistedBaseline_expectSurvivesColdStart() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = makeStorage(directory: dir)
        await first.recordMonitorRegistration(identifier: "geo_1", transitionTypes: [.enter, .exit], initialState: .exit, center: LocationData(latitude: 10, longitude: 20), radius: 100)
        #expect(await first.recordMonitorEvent(.enter, forIdentifier: "geo_1") == .deliver) // walked in
        // Cold-wake: a fresh storage instance compares CLMonitor's replay against the pre-kill state
        // (inside). No re-registration happened, so the baseline is intact.
        let afterRelaunch = makeStorage(directory: dir)
        #expect(await afterRelaunch.recordMonitorEvent(.enter, forIdentifier: "geo_1") == .suppressedNoChange)
        #expect(await afterRelaunch.recordMonitorEvent(.exit, forIdentifier: "geo_1") == .deliver)
    }

    @Test
    func getMonitorRegionRecords_givenRegistrationsAndEvents_expectGeometryAndBaselinesReturned() async {
        // The adopt-time re-arm rebuilds CLMonitor conditions from this snapshot, so it must carry
        // the registered geometry and the CURRENT baseline (not the registration-time state).
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
        // The trigger is never in `businessIds` but is always registered; pruning it would discard
        // the baseline that makes its EXIT deliverable.
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
        // The regression. A region evicted while the device is inside keeps a `.enter` baseline that
        // no EXIT ever balances, because it is no longer monitored. Re-registering the same circle
        // later preserves that baseline, so the arrival on a genuine revisit reads as no change and
        // is dropped. Pruning on eviction is what keeps the revisit deliverable.
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
        // Pruning must not touch a region that is still registered: its baseline is what keeps an
        // unchanged re-register silent instead of re-delivering the state the device is already in.
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
}
