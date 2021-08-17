@testable import CIO
import Foundation
import XCTest

class CustomerIOTest: UnitTest {
    // MARK: singleton, shared instance integration testing

    func test_shared_givenNotInitialized_expectNotLoadCredentialsOnInit() {
        let instance = CustomerIO()

        XCTAssertNil(instance.credentials)
    }

    func test_shared_givenInitializeBefore_expectLoadCredentialsOnInit() {
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

    func test_shared_givenInitSeparateInstance_expectSeparateCredentials() {
        let givenSiteIdSharedInstance = String.random
        let givenSiteIdNewInstance = String.random

        let sharedInstance = CustomerIO()
        sharedInstance.setCredentials(siteId: givenSiteIdSharedInstance, apiKey: String.random, region: Region.US)
        let newInstance = CustomerIO(siteId: givenSiteIdNewInstance, apiKey: String.random, region: Region.EU)

        XCTAssertNotNil(sharedInstance.credentials)
        XCTAssertNotNil(newInstance.credentials)

        XCTAssertEqual(sharedInstance.credentials?.siteId, givenSiteIdSharedInstance)
        XCTAssertEqual(newInstance.credentials?.siteId, givenSiteIdNewInstance)

        XCTAssertNotEqual(sharedInstance.credentials?.apiKey, newInstance.credentials?.apiKey)
    }

    // MARK: non-shared singleton instance integration testing

    func test_instance_expectInitializedInstance() {
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
}
