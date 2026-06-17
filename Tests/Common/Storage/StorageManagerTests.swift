@testable import CioInternalCommon
import SyncSqlCipher
import XCTest

// StorageManager is tested against an in-memory SQLCipher database so there
// is no file-system state to clean up between runs.
class StorageManagerTests: XCTestCase {
    private var storage: StorageManager!

    override func setUp() {
        super.setUp()
        let db = try! Database(path: ":memory:", key: "testkey", walMode: false)
        storage = StorageManager(db: db, cdpApiKey: "testkey")
        try! storage.runMigrations()
    }

    // MARK: - Schema

    func test_runMigrations_isIdempotent() throws {
        XCTAssertNoThrow(try storage.runMigrations())
    }

    // MARK: - sdk_meta

    func test_getMetaValue_forUnknownKey_returnsNil() throws {
        XCTAssertNil(try storage.getMetaValue("nonexistent"))
    }

    func test_setAndGetMetaValue_roundTrip() throws {
        try storage.setMetaValue("hello", for: "greeting")

        XCTAssertEqual(try storage.getMetaValue("greeting"), "hello")
    }

    func test_setMetaValue_overwritesExistingValue() throws {
        try storage.setMetaValue("first", for: "key")
        try storage.setMetaValue("second", for: "key")

        XCTAssertEqual(try storage.getMetaValue("key"), "second")
    }

    func test_setMetaValue_withNil_deletesExistingValue() throws {
        try storage.setMetaValue("value", for: "key")
        try storage.setMetaValue(nil, for: "key")

        XCTAssertNil(try storage.getMetaValue("key"))
    }

    func test_setMetaValue_withNil_whenKeyAbsent_doesNotThrow() {
        XCTAssertNoThrow(try storage.setMetaValue(nil, for: "nonexistent"))
    }

    func test_metaValues_areIsolatedByKey() throws {
        try storage.setMetaValue("a", for: "key-a")
        try storage.setMetaValue("b", for: "key-b")

        XCTAssertEqual(try storage.getMetaValue("key-a"), "a")
        XCTAssertEqual(try storage.getMetaValue("key-b"), "b")
    }
}
