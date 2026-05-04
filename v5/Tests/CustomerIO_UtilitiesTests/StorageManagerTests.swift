import CustomerIO_Utilities
import Foundation
import SqlCipherKit
import Testing

// MARK: - Helpers

private func makeTempStorage() async throws -> StorageManager {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString + ".db")
    let db = try Database(path: url.path, key: "test-key")
    let storage = StorageManager(db: db)
    try await storage.runMigrations()
    return storage
}

// MARK: - StorageManager

@Suite struct StorageManagerTests {
    @Test func setAndGetString_identityTable() async throws {
        let storage = try await makeTempStorage()
        try await storage.setString("abc", for: "foo", in: "identity")
        let value = try await storage.getString("foo", from: "identity")
        #expect(value == "abc")
    }

    @Test func setString_nilDeletesRow() async throws {
        let storage = try await makeTempStorage()
        try await storage.setString("bar", for: "baz", in: "identity")
        try await storage.setString(nil, for: "baz", in: "identity")
        let value = try await storage.getString("baz", from: "identity")
        #expect(value == nil)
    }

    @Test func setAndGetMetaValue() async throws {
        let storage = try await makeTempStorage()
        try await storage.setMetaValue("v1", for: "k1")
        let value = try await storage.getMetaValue("k1")
        #expect(value == "v1")
    }
}
