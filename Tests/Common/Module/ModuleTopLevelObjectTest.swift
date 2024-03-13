@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class ModuleTopLevelObjectTest: UnitTest {
    override func setUp() {
        super.setUp()

        ModuleTopLevelObjectStub.reset()
    }

    // MARK: initialize

    func test_initialize_expectOnlyAbleToInitializeOnce_expectInitializeThreadSafe() {
        // Run test multiple times to ensure thread safety. To try and catch a race condition, if one will exist.
        let numberOfTimesToTestInitialize = 50

        let expectAllThreadsToComplete = expectation(description: "All threads should complete")
        expectAllThreadsToComplete.expectedFulfillmentCount = numberOfTimesToTestInitialize

        XCTAssertEqual(ModuleTopLevelObjectStub.shared.initializeCount, 0)

        // Initialize the module twice, on different threads.
        // This tests:
        // 1. Only able to initialize the module once.
        // 2. Initialize is thread-safe.
        for _ in 0 ..< numberOfTimesToTestInitialize {
            runOnBackground {
                ModuleTopLevelObjectStub.initialize()

                expectAllThreadsToComplete.fulfill()
            }
        }

        waitForExpectations()

        // Even though we call initialize multiple times, the initialize count should only be 1.
        XCTAssertEqual(ModuleTopLevelObjectStub.shared.initializeCount, 1)
    }
}

protocol ModuleTopLevelObjectStubInstance {}

// Simple stub that has the same public API as SDK module subclasses.
class ModuleTopLevelObjectStub: ModuleTopLevelObject<ModuleTopLevelObjectStubInstance>, ModuleTopLevelObjectStubInstance {
    @Atomic static var shared = ModuleTopLevelObjectStub()

    @Atomic public private(set) var initializeCount = 0

    static func reset() {
        shared = ModuleTopLevelObjectStub()
    }

    init() {
        super.init(moduleName: "Stub")
    }

    static func initialize() {
        // This is a public function that customers can call to initialize the module.
        shared.initializeModuleIfNotAlready {
            shared.initializeCount += 1

            return shared
        }
    }
}
