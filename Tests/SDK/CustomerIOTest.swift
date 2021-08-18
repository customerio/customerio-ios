@testable import CIO
import Foundation
import XCTest

class CustomerIOTest: UnitTest {
    // MARK: credentials

    func test_sharedInstance_givenNotInitialized_expectNotLoadCredentialsOnInit() {
        XCTAssertNil(CustomerIO.instance.credentials)
    }

    func test_sharedInstance_givenInitializeBefore_expectLoadCredentialsOnInit() {
        let givenSiteId = String.random

        // First, set the credentials on the shared instance
        CustomerIO.initialize(siteId: givenSiteId, apiKey: String.random, region: Region.EU)
        // next, create an instance of the shared instance and see if credentials loads
        var instance: CustomerIO!
        instance = CustomerIO()
        XCTAssertNotNil(instance.credentials)
        instance = nil // try to remove instance from memory simulating app removed from memory
        XCTAssertNil(instance)

        instance = CustomerIO()
        XCTAssertNotNil(instance.credentials)
        XCTAssertEqual(instance.credentials?.siteId, givenSiteId)
    }

    func test_sharedInstance_givenInitSeparateInstance_expectSeparateCredentials() {
        let givenSiteIdSharedInstance = String.random
        let givenSiteIdNewInstance = String.random

        CustomerIO.instance.setCredentials(siteId: givenSiteIdSharedInstance, apiKey: String.random, region: Region.US)
        let newInstance = CustomerIO(siteId: givenSiteIdNewInstance, apiKey: String.random, region: Region.EU)

        XCTAssertNotNil(CustomerIO.instance.credentials)
        XCTAssertNotNil(newInstance.credentials)

        XCTAssertEqual(CustomerIO.instance.credentials?.siteId, givenSiteIdSharedInstance)
        XCTAssertEqual(newInstance.credentials?.siteId, givenSiteIdNewInstance)

        XCTAssertNotEqual(CustomerIO.instance.credentials?.apiKey, newInstance.credentials?.apiKey)
    }

    func test_newInstance_expectInitializedInstance() {
        let givenSiteId = String.random

        let actual = CustomerIO(siteId: givenSiteId, apiKey: String.random, region: Region.EU)

        XCTAssertNotNil(actual.credentials)
        XCTAssertEqual(actual.credentials?.siteId, givenSiteId)
    }

    func test_init_givenAccessMultipleThreads_expectSameValues() {
        let givenSiteId = String.random

        let actual = CustomerIO(siteId: givenSiteId, apiKey: String.random, region: Region.EU)

        DispatchQueue.global(qos: .background).sync {
            XCTAssertNotNil(actual.credentials)
        }

        XCTAssertNotNil(actual.credentials)
    }

    // MARK: config

    func test_config_expectNotNilOnInit() {
        let instance = CustomerIO(siteId: String.random, apiKey: String.random, region: Region.US)

        XCTAssertNotNil(CustomerIO.instance.sdkConfig)
        XCTAssertNotNil(instance.sdkConfig)
    }

    func test_config_sharedInstance_givenModifyConfig_expectSetConfigOnInstance() {
        XCTAssertNil(CustomerIO.instance.sdkConfig.trackingApiUrl)

        CustomerIO.config {
            $0.trackingApiUrl = ""
        }

        XCTAssertNotNil(CustomerIO.instance.sdkConfig.trackingApiUrl)
    }

    func test_config_expectSharedInstanceConfigStartingValueForModifyingConfig() {
        CustomerIO.config {
            $0.trackingApiUrl = ""
        }

        let instance = CustomerIO(siteId: String.random, apiKey: String.random, region: Region.US)
        XCTAssertNotNil(instance.sdkConfig.trackingApiUrl)

        instance.config { actual in
            XCTAssertNotNil(actual.trackingApiUrl)
        }
    }

    func test_config_givenMultipleInstances_expectDifferentConfig() {
        let instance1 = CustomerIO(siteId: String.random, apiKey: String.random, region: Region.US)
        let instance2 = CustomerIO(siteId: String.random, apiKey: String.random, region: Region.US)

        XCTAssertNil(instance1.sdkConfig.trackingApiUrl)
        XCTAssertNil(instance2.sdkConfig.trackingApiUrl)

        instance1.config {
            $0.trackingApiUrl = ""
        }

        XCTAssertNotNil(instance1.sdkConfig.trackingApiUrl)
        XCTAssertNil(instance2.sdkConfig.trackingApiUrl)
    }

    func test_config_givenAccessMultipleThreads_expectSameValue() {
        let instance = CustomerIO(siteId: String.random, apiKey: String.random, region: Region.US)

        DispatchQueue.global(qos: .background).sync {
            instance.config {
                $0.trackingApiUrl = ""
            }
        }

        XCTAssertNotNil(instance.sdkConfig.trackingApiUrl)
    }
}
