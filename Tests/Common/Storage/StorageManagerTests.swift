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
        storage = StorageManager(db: db)
        try! storage.runMigrations()
    }

    // MARK: - Schema

    func test_runMigrations_isIdempotent() throws {
        // Running a second time must not throw (all tables use IF NOT EXISTS).
        XCTAssertNoThrow(try storage.runMigrations())
    }

}
