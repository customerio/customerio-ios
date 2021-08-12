@testable import CIO
import Foundation
import XCTest

class CustomerIOTest: UnitTest {
    // MARK: singleton, shared instance integration testing

    func test_shared_givenNotConfigured_expectNotLoadConfigurationOnInit() {
        let instance = CustomerIO()

        XCTAssertNil(instance.config)
    }

    func test_shared_givenConfiguredBefore_expectLoadConfigurationOnInit() {
        let givenSiteId = String.random

        // First, set the config on the shared instance
        CustomerIO.config(siteId: givenSiteId, apiKey: String.random, region: Region.EU)
        // next, create an instance of the shared instance and see if config loads
        var instance: CustomerIO!
        instance = CustomerIO()
        XCTAssertNotNil(instance.config)
        instance = nil // try to remove instance from memory simulating app removed from memory
        XCTAssertNil(instance)

        instance = CustomerIO()
        XCTAssertNotNil(instance.config)
        XCTAssertEqual(instance.config?.siteId, givenSiteId)
    }

    func test_shared_givenConfigureSeparateInstance_expectSeparateConfig() {
        let givenSiteIdSharedInstance = String.random
        let givenSiteIdNewInstance = String.random

        let sharedInstance = CustomerIO()
        sharedInstance.setConfig(siteId: givenSiteIdSharedInstance, apiKey: String.random, region: Region.US)
        let newInstance = CustomerIO(siteId: givenSiteIdNewInstance, apiKey: String.random, region: Region.EU)

        XCTAssertNotNil(sharedInstance.config)
        XCTAssertNotNil(newInstance.config)

        XCTAssertEqual(sharedInstance.config?.siteId, givenSiteIdSharedInstance)
        XCTAssertEqual(newInstance.config?.siteId, givenSiteIdNewInstance)

        XCTAssertNotEqual(sharedInstance.config?.apiKey, newInstance.config?.apiKey)
    }

    // MARK: non-shared singleton instance integration testing

    func test_instance_expectConfiguredInstance() {
        let givenSiteId = String.random

        let actual = CustomerIO(siteId: givenSiteId, apiKey: String.random, region: Region.EU)

        XCTAssertNotNil(actual.config)

        XCTAssertEqual(actual.config?.siteId, givenSiteId)
    }

    func test_config_givenAccessMultipleThreads_expectSameValues() {
        let givenSiteId = String.random

        let actual = CustomerIO(siteId: givenSiteId, apiKey: String.random, region: Region.EU)

        DispatchQueue.global(qos: .background).sync {
            XCTAssertNotNil(actual.config)
        }

        XCTAssertNotNil(actual.config)
    }
}
