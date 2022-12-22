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

    func test_init_setCredentials_expectAppendSiteId() {
        let sharedGivenSiteId = String.random
        let instanceGivenSiteId = String.random

        CustomerIO.initialize(siteId: sharedGivenSiteId, apiKey: String.random, region: Region.EU)
        XCTAssertEqual(CustomerIO.shared.globalData.siteIds, [sharedGivenSiteId])

        _ = CustomerIO(siteId: instanceGivenSiteId, apiKey: String.random)

        XCTAssertEqualEither([
            [sharedGivenSiteId, instanceGivenSiteId],
            [instanceGivenSiteId, sharedGivenSiteId]
        ], actual: CustomerIO.shared.globalData.siteIds)
    }

    func test_sharedInstance_expectImplementationLoadedAfterInitialize() {
        XCTAssertNil(CustomerIO.shared.implementation)

        CustomerIO.initialize(siteId: String.random, apiKey: String.random, region: Region.EU)

        XCTAssertNotNil(CustomerIO.shared.implementation)
    }

    func test_sharedInstance_givenSharedInstanceSiteIdSet_givenCredentialsNotYet_expectImplementationNotLoaded() {
        globalDataStore.sharedInstanceSiteId = String.random

        _ = CustomerIO()

        XCTAssertNil(CustomerIO.shared.implementation)
    }

    func test_initializeSdk_givenNoConfig_expectSetDefaultConfigOptions() {
        let givenSiteId = String.random

        _ = CustomerIO(siteId: givenSiteId, apiKey: String.random, region: Region.EU)

        let config = DIGraph.getInstance(siteId: givenSiteId).sdkConfigStore.config

        XCTAssertEqual(config.trackingApiUrl, Region.EU.productionTrackingUrl)
    }

    func test_initialize_expectAddModuleHooks_expectRunCleanup() {
        _ = CustomerIO(siteId: testSiteId, apiKey: String.random, region: Region.EU)

        XCTAssertEqual(hooksManagerMock.addCallsCount, 1)
        XCTAssertEqual(hooksManagerMock.addReceivedArguments?.key, .tracking)

        XCTAssertEqual(cleanupRepositoryMock.cleanupCallsCount, 1)
    }

    // MARK: deinit

    func test_givenNilObject_expectDeinit() {
        var cio: CustomerIO? = CustomerIO(siteId: String.random, apiKey: String.random)

        cio = nil

        XCTAssertNil(cio)
    }
}
