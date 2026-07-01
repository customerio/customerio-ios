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

struct LiveActivityMigrationTests {
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

// MARK: - getRegistrationSignature

struct LiveActivityRegistrationGetTests {
    @Test func getSignature_returnsNil_whenNoRecordExists() throws {
        let storage = try makeTempStorage()
        #expect(try storage.getRegistrationSignature(activityType: "OrderActivity") == nil)
    }

    @Test func getSignature_returnsNil_forUnknownActivityType() throws {
        let storage = try makeTempStorage()
        try storage.setRegistrationSignature(activityType: "OrderActivity", signature: "aabbcc|user-1")
        #expect(try storage.getRegistrationSignature(activityType: "ShipmentActivity") == nil)
    }

    @Test func getSignature_returnsStoredSignature() throws {
        let storage = try makeTempStorage()
        try storage.setRegistrationSignature(activityType: "OrderActivity", signature: "deadbeef|user-1")
        #expect(try storage.getRegistrationSignature(activityType: "OrderActivity") == "deadbeef|user-1")
    }
}

// MARK: - setRegistrationSignature

struct LiveActivityRegistrationSetTests {
    @Test func setSignature_persistsValue() throws {
        let storage = try makeTempStorage()
        try storage.setRegistrationSignature(activityType: "OrderActivity", signature: "cafebabe|user-1")
        #expect(try storage.getRegistrationSignature(activityType: "OrderActivity") == "cafebabe|user-1")
    }

    @Test func setSignature_upserts_onConflict() throws {
        let storage = try makeTempStorage()
        try storage.setRegistrationSignature(activityType: "OrderActivity", signature: "first|user-1")
        try storage.setRegistrationSignature(activityType: "OrderActivity", signature: "second|user-2")
        #expect(try storage.getRegistrationSignature(activityType: "OrderActivity") == "second|user-2")
    }

    @Test func setSignature_storesIndependentlyPerActivityType() throws {
        let storage = try makeTempStorage()
        try storage.setRegistrationSignature(activityType: "OrderActivity", signature: "order|user-1")
        try storage.setRegistrationSignature(activityType: "ShipmentActivity", signature: "ship|user-1")
        #expect(try storage.getRegistrationSignature(activityType: "OrderActivity") == "order|user-1")
        #expect(try storage.getRegistrationSignature(activityType: "ShipmentActivity") == "ship|user-1")
    }
}

// MARK: - clearAllLiveActivityRegistrations

struct LiveActivityRegistrationClearTests {
    @Test func clear_removesAllRecords() throws {
        let storage = try makeTempStorage()
        try storage.setRegistrationSignature(activityType: "OrderActivity", signature: "aaa|u")
        try storage.setRegistrationSignature(activityType: "ShipmentActivity", signature: "bbb|u")
        try storage.clearAllLiveActivityRegistrations()
        #expect(try storage.getRegistrationSignature(activityType: "OrderActivity") == nil)
        #expect(try storage.getRegistrationSignature(activityType: "ShipmentActivity") == nil)
    }

    @Test func clear_isNoOp_whenTableIsAlreadyEmpty() throws {
        let storage = try makeTempStorage()
        try storage.clearAllLiveActivityRegistrations()
        #expect(try storage.getRegistrationSignature(activityType: "Any") == nil)
    }

    @Test func setSignature_afterClear_persistsCorrectly() throws {
        let storage = try makeTempStorage()
        try storage.setRegistrationSignature(activityType: "OrderActivity", signature: "old|u")
        try storage.clearAllLiveActivityRegistrations()
        try storage.setRegistrationSignature(activityType: "OrderActivity", signature: "new|u")
        #expect(try storage.getRegistrationSignature(activityType: "OrderActivity") == "new|u")
    }
}
