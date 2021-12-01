@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class CustomerIOTest: UnitTest {
    private let globalDataStore = CioGlobalDataStore()

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

    func test_sharedInstance_givenInitializeBefore_expectLoadCredentialsOnInit() {
        let givenSiteId = String.random

        XCTAssertNil(CustomerIO.shared.implementation)

        // First, set the credentials on the shared instance
        CustomerIO.initialize(siteId: givenSiteId, apiKey: String.random, region: Region.EU)
        CustomerIO.resetSharedInstance()
        _ = CustomerIO()

        XCTAssertNotNil(CustomerIO.shared.implementation)
        XCTAssertEqual(CustomerIO.shared.siteId, givenSiteId)
    }

    func test_newInstance_expectInitializedInstance() {
        let givenSiteId = String.random

        let actual = CustomerIO(siteId: givenSiteId, apiKey: String.random, region: Region.EU)

        XCTAssertNotNil(actual.implementation)
        XCTAssertEqual(actual.siteId, givenSiteId)
    }

    func test_initializeSdk_givenNoConfig_expectSetDefaultConfigOptions() {
        let givenSiteId = String.random

        _ = CustomerIO(siteId: givenSiteId, apiKey: String.random, region: Region.EU)

        let config = DITracking.getInstance(siteId: givenSiteId).sdkConfigStore.config

        XCTAssertEqual(config.trackingApiUrl, Region.EU.productionTrackingUrl)
    }

    // MARK: deinit

    func test_givenNilObject_expectDeinit() {
        var cio: CustomerIO? = CustomerIO(siteId: String.random, apiKey: String.random)

        cio = nil

        XCTAssertNil(cio)
    }
}
