@testable import CioInternalCommon
@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class BaseMigrationTest: IntegrationTest {
    private var migration: MigrationSubclassForTest!

    override func setUp() {
        super.setUp()

        resetMigrationSubclass()
    }

    // MARK: run

    func test_run_givenMigrationNotRunBefore_expectMigrationRun() {
        XCTAssertEqual(migration.performMigrationCount, 0)

        migration.run()

        XCTAssertEqual(migration.performMigrationCount, 1)
    }

    func test_run_givenMigrationRunBefore_expectMigrationNotRun() {
        XCTAssertEqual(migration.performMigrationCount, 0)
        migration.run()
        XCTAssertEqual(migration.performMigrationCount, 1)

        // Try running migration again and see it does not run again.
        migration.run()
        XCTAssertEqual(migration.performMigrationCount, 1)

        // Test that even if SDK dependencies get re-created, the migration will still not run again.
        resetMigrationSubclass()
        XCTAssertEqual(migration.performMigrationCount, 0)
        migration.run()
        XCTAssertEqual(migration.performMigrationCount, 0)
    }
}

extension BaseMigrationTest {
    func resetMigrationSubclass() {
        migration = MigrationSubclassForTest(migrationName: "migration-subclass-for-test", destinationDiGraph: diGraph)
    }

    class MigrationSubclassForTest: BaseMigration {
        var performMigrationCount = 0

        override func performMigration() {
            performMigrationCount += 1
        }
    }
}
