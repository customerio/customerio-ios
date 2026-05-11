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
    func purgeExpiredCooldowns_givenExpiredKeys_expectRemoved() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        let t1 = Date(timeIntervalSince1970: 1700000000)
        let t2 = Date(timeIntervalSince1970: 1700001000)
        await storage.recordEventCooldown(key: "geo_1:enter", timestamp: t1)
        await storage.recordEventCooldown(key: "geo_2:enter", timestamp: t2)
        await storage.purgeExpiredCooldowns(keys: ["geo_1:enter"])
        let cooldowns = await storage.getEventCooldowns()
        #expect(cooldowns.count == 1)
        #expect(cooldowns["geo_1:enter"] == nil)
        #expect(cooldowns["geo_2:enter"] == t2)
    }

    @Test
    func purgeExpiredCooldowns_givenEmptyKeys_expectNoChange() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = makeStorage(directory: dir)
        await storage.recordEventCooldown(key: "geo_1:enter", timestamp: Date())
        await storage.purgeExpiredCooldowns(keys: [])
        let cooldowns = await storage.getEventCooldowns()
        #expect(cooldowns.count == 1)
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
                            await storage.purgeExpiredCooldowns(keys: ["geo_\(i):enter"])
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
