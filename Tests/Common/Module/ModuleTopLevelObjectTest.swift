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
        // I do not suggest running test < 100 times. When bugs existed because of not being thread safe, the test may have to run 50 times until it fails.
        runTest(numberOfTimes: 100) {
            let expectAllThreadsToComplete = expectation(description: "All threads should complete")
            expectAllThreadsToComplete.expectedFulfillmentCount = 2

            XCTAssertEqual(ModuleTopLevelObjectStub.shared.initializeCount, 0)

            // Initialize the module twice, on different threads.
            // This tests:
            // 1. Only able to initialize the module once.
            // 2. Initialize is thread-safe.
            runOnBackground {
                ModuleTopLevelObjectStub.initialize()

                expectAllThreadsToComplete.fulfill()
            }

            runOnBackground {
                ModuleTopLevelObjectStub.initialize()

                expectAllThreadsToComplete.fulfill()
            }

            waitForExpectations()

            // Even though we call initialize twice, the initialize count should only be 1.
            XCTAssertEqual(ModuleTopLevelObjectStub.shared.initializeCount, 1)
        }
    }
}

protocol ModuleTopLevelObjectStubInstance {}

// Simple stub that has the same public API as SDK module subclasses.
class ModuleTopLevelObjectStub: ModuleTopLevelObject<ModuleTopLevelObjectStubInstance>, ModuleTopLevelObjectStubInstance {
    @Atomic static var shared = ModuleTopLevelObjectStub()

    public private(set) var initializeCount = 0

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
