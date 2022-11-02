@testable import CioTracking
@testable import Common
import Foundation
import SharedTests
import XCTest

class CustomerIOTest: UnitTest {
    private let globalDataStore = CioGlobalDataStore()
    private let cleanupRepositoryMock = CleanupRepositoryMock()
    private let hooksManagerMock = HooksManagerMock()

    override func setUp() {
        super.setUp()

        diGraph.override(value: cleanupRepositoryMock, forType: CleanupRepository.self)
        diGraph.override(value: hooksManagerMock, forType: HooksManager.self)
    }

    // MARK: init

    func test_sharedInstance_expectImplementationLoadedAfterInitialize() {
        XCTAssertNil(CustomerIO.shared.implementation)

        CustomerIO.initialize(siteId: String.random, apiKey: String.random, region: Region.EU)

        XCTAssertNotNil(CustomerIO.shared.implementation)
    }

    // TODO: move this test to implementation test class
//    func test_initialize_expectAddModuleHooks_expectRunCleanup() {
//        CustomerIO.initialize(siteId: testSiteId, apiKey: String.random, region: Region.EU)
//
//        XCTAssertEqual(hooksManagerMock.addCallsCount, 1)
//        XCTAssertEqual(hooksManagerMock.addReceivedArguments?.key, .tracking)
//
//        XCTAssertEqual(cleanupRepositoryMock.cleanupCallsCount, 1)
//    }
}
