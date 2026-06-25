import CioInternalCommon
import Foundation
import Testing

@testable import CioLiveActivities

// MARK: - Helpers

private func makeTempStorage() throws -> StorageManager {
    let db = try Database(path: ":memory:", key: "test-key", walMode: false)
    let storage = StorageManager(db: db, cdpApiKey: "test-key")
    try storage.runMigrations()
    return storage
}

// MARK: - Migration

@Suite struct LiveActivityMigrationTests {

    @Test func migration_createsTable_withoutError() throws {
        _ = try makeTempStorage()
    }

    @Test func migration_isIdempotent() throws {
        let db = try Database(path: ":memory:", key: "test-key", walMode: false)
        let storage = StorageManager(db: db, cdpApiKey: "test-key")
        try storage.runMigrations()
        try storage.runMigrations()
    }
}

// MARK: - getLiveActivityPushToken

@Suite struct LiveActivityStorageGetTests {

    @Test func getToken_returnsNil_whenNoRecordExists() throws {
        let storage = try makeTempStorage()
        let token = try storage.getLiveActivityPushToken(activityType: "OrderActivity")
        #expect(token == nil)
    }

    @Test func getToken_returnsNil_forUnknownActivityType() throws {
        let storage = try makeTempStorage()
        try storage.setLiveActivityPushToken(activityType: "OrderActivity", tokenHex: "aabbcc")
        let token = try storage.getLiveActivityPushToken(activityType: "ShipmentActivity")
        #expect(token == nil)
    }

    @Test func getToken_returnsStoredToken() throws {
        let storage = try makeTempStorage()
        try storage.setLiveActivityPushToken(activityType: "OrderActivity", tokenHex: "deadbeef")
        let token = try storage.getLiveActivityPushToken(activityType: "OrderActivity")
        #expect(token == "deadbeef")
    }
}

// MARK: - setLiveActivityPushToken

@Suite struct LiveActivityStorageSetTests {

    @Test func setToken_persistsTokenHex() throws {
        let storage = try makeTempStorage()
        try storage.setLiveActivityPushToken(activityType: "OrderActivity", tokenHex: "cafebabe")
        let token = try storage.getLiveActivityPushToken(activityType: "OrderActivity")
        #expect(token == "cafebabe")
    }

    @Test func setToken_upserts_onConflict() throws {
        let storage = try makeTempStorage()
        try storage.setLiveActivityPushToken(activityType: "OrderActivity", tokenHex: "first")
        try storage.setLiveActivityPushToken(activityType: "OrderActivity", tokenHex: "second")
        let token = try storage.getLiveActivityPushToken(activityType: "OrderActivity")
        #expect(token == "second")
    }

    @Test func setToken_storesIndependentlyPerActivityType() throws {
        let storage = try makeTempStorage()
        try storage.setLiveActivityPushToken(activityType: "OrderActivity", tokenHex: "token-order")
        try storage.setLiveActivityPushToken(activityType: "ShipmentActivity", tokenHex: "token-ship")
        let orderToken = try storage.getLiveActivityPushToken(activityType: "OrderActivity")
        let shipToken = try storage.getLiveActivityPushToken(activityType: "ShipmentActivity")
        #expect(orderToken == "token-order")
        #expect(shipToken == "token-ship")
    }
}

// MARK: - clearAllLiveActivityPushTokens

@Suite struct LiveActivityStorageClearTests {

    @Test func clear_removesAllRecords() throws {
        let storage = try makeTempStorage()
        try storage.setLiveActivityPushToken(activityType: "OrderActivity", tokenHex: "aaa")
        try storage.setLiveActivityPushToken(activityType: "ShipmentActivity", tokenHex: "bbb")
        try storage.clearAllLiveActivityPushTokens()
        let order = try storage.getLiveActivityPushToken(activityType: "OrderActivity")
        let ship = try storage.getLiveActivityPushToken(activityType: "ShipmentActivity")
        #expect(order == nil)
        #expect(ship == nil)
    }

    @Test func clear_isNoOp_whenTableIsAlreadyEmpty() throws {
        let storage = try makeTempStorage()
        try storage.clearAllLiveActivityPushTokens()
        let token = try storage.getLiveActivityPushToken(activityType: "Any")
        #expect(token == nil)
    }

    @Test func setToken_afterClear_persistsCorrectly() throws {
        let storage = try makeTempStorage()
        try storage.setLiveActivityPushToken(activityType: "OrderActivity", tokenHex: "old")
        try storage.clearAllLiveActivityPushTokens()
        try storage.setLiveActivityPushToken(activityType: "OrderActivity", tokenHex: "new")
        let token = try storage.getLiveActivityPushToken(activityType: "OrderActivity")
        #expect(token == "new")
    }
}
