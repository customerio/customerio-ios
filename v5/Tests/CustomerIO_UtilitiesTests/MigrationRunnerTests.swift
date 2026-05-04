import Foundation
import Testing

@testable import CustomerIO_Utilities
@testable import SqlCipherKit

// Use makeTempStorage from StorageManagerTests.swift

// Local helper for in-memory StorageManager
func makeInMemoryStorage() async throws -> StorageManager {
    let db = try Database(path: ":memory:", key: "testkey")
    let storage = StorageManager(db: db)
    try await storage.runMigrations(extra: [])
    return storage
}

@Suite struct MigrationRunnerTests {
    @Test func legacySeeds_readsUserDefaults() async throws {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "identifiedProfileId")
        defaults.removeObject(forKey: "CioAnalytics.anonymousId")
        defaults.removeObject(forKey: "CioGlobalDataStore.pushToken")
        defaults.set("profile", forKey: "identifiedProfileId")
        defaults.set("anon", forKey: "CioAnalytics.anonymousId")
        defaults.set("token", forKey: "CioGlobalDataStore.pushToken")
        let runner = MigrationRunner(storage: try await makeInMemoryStorage())
        let seeds = runner.legacySeeds()
        #expect(seeds.profileId == "profile")
        #expect(seeds.anonymousId == "anon")
        #expect(seeds.pushToken == "token")
    }

    @Test func markComplete_and_isComplete() async throws {
        let storage = try await makeInMemoryStorage()
        let runner = MigrationRunner(storage: storage)
        #expect(await runner.isComplete() == false)
        try await runner.markComplete()
        #expect(await runner.isComplete() == true)
    }
}
