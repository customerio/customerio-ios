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

        DITracking.getInstance(siteId: testSiteId)
            .override(.cleanupRepository, value: cleanupRepositoryMock, forType: CleanupRepository.self)
        diGraph.override(.hooksManager, value: hooksManagerMock, forType: HooksManager.self)
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
