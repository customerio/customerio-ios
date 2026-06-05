@testable import CioInternalCommon
@testable import CioLocation
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
}
