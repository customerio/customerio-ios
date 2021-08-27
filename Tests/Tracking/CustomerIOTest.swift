@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class CustomerIOTest: UnitTest {
    private var customerIO: CustomerIO!

    private var identifyRepositoryMock: IdentifyRepositoryMock!

    override func setUp() {
        super.setUp()

        identifyRepositoryMock = IdentifyRepositoryMock()

        customerIO = CustomerIO(credentialsStore: nil, sdkConfig: SdkConfig(),
                                identifyRepository: identifyRepositoryMock, keyValueStorage: nil)
    }

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
        let givenTrackingApiUrl = String.random

        XCTAssertNotEqual(CustomerIO.instance.sdkConfig.trackingApiUrl, givenTrackingApiUrl)

        CustomerIO.config {
            $0.trackingApiUrl = givenTrackingApiUrl
        }

        XCTAssertEqual(CustomerIO.instance.sdkConfig.trackingApiUrl, givenTrackingApiUrl)
    }

    func test_config_expectSharedInstanceConfigStartingValueForModifyingConfig() {
        let givenUrl = String.random

        CustomerIO.config {
            $0.trackingApiUrl = givenUrl
        }

        let instance = CustomerIO(siteId: String.random, apiKey: String.random, region: Region.US)
        XCTAssertEqual(instance.sdkConfig.trackingApiUrl, givenUrl)

        instance.config { actual in
            XCTAssertEqual(actual.trackingApiUrl, givenUrl)
        }
    }

    func test_config_givenMultipleInstances_expectDifferentConfig() {
        let instance1 = CustomerIO(siteId: String.random, apiKey: String.random, region: Region.US)
        let instance2 = CustomerIO(siteId: String.random, apiKey: String.random, region: Region.US)

        XCTAssertEqual(instance1.sdkConfig.trackingApiUrl, instance2.sdkConfig.trackingApiUrl)

        instance1.config {
            $0.trackingApiUrl = String.random
        }

        XCTAssertNotEqual(instance1.sdkConfig.trackingApiUrl, instance2.sdkConfig.trackingApiUrl)
    }

    func test_config_givenAccessMultipleThreads_expectSameValue() {
        let givenUrl = String.random

        let instance = CustomerIO(siteId: String.random, apiKey: String.random, region: Region.US)

        DispatchQueue.global(qos: .background).sync {
            instance.config {
                $0.trackingApiUrl = givenUrl
            }
        }

        XCTAssertEqual(instance.sdkConfig.trackingApiUrl, givenUrl)
    }

    func test_config_givenSetConfig_expectSetDefaultValuesOnConfig() {
        let instance = CustomerIO(siteId: String.random, apiKey: String.random, region: Region.EU)

        // Call config but don't set anything to see if default values get set
        instance.config { _ in }

        XCTAssertEqual(instance.sdkConfig.trackingApiUrl, Region.EU.productionTrackingUrl)
    }

    // MARK: setDefaultValuesSdkConfig

    func test_setDefaultValuesSdkConfig_givenUnmodifiedConfigObject_expectSetDefaultValuesOnConfig() {
        let instance = CustomerIO(siteId: String.random, apiKey: String.random, region: Region.EU)
        let unmodifiedSdkConfig = instance.sdkConfig

        let actual = instance.setDefaultValuesSdkConfig(config: unmodifiedSdkConfig)

        XCTAssertEqual(actual.trackingApiUrl, Region.EU.productionTrackingUrl)
    }

    func test_setDefaultValuesSdkConfig_givenModifiedTrackingApiUrl_expectDoNotChangeIt() {
        let givenUrl = String.random
        let instance = CustomerIO(siteId: String.random, apiKey: String.random, region: Region.EU)
        instance.sdkConfig.trackingApiUrl = givenUrl

        let actual = instance.setDefaultValuesSdkConfig(config: instance.sdkConfig)

        XCTAssertEqual(actual.trackingApiUrl, givenUrl)
    }

    // MARK: identify

    func test_identify_givenSdkNotInialized_expectFailureResult() {
        customerIO = CustomerIO(credentialsStore: nil, sdkConfig: SdkConfig(), identifyRepository: nil,
                                keyValueStorage: nil)

        let expect = expectation(description: "Expect to complete identify")
        customerIO.identify(identifier: String.random) { result in
            guard case .failure(let error) = result else { return XCTFail() }
            guard case .notInitialized = error else { return XCTFail() }

            XCTAssertFalse(self.identifyRepositoryMock.mockCalled)

            expect.fulfill()
        }

        waitForExpectations()
    }

    func test_identify_expectCallRepository() {
        let givenIdentifier = String.random
        let givenEmail = EmailAddress.randomEmail

        identifyRepositoryMock.addOrUpdateCustomerClosure = { actualIdentifier, actualEmail, onComplete in
            XCTAssertEqual(givenIdentifier, actualIdentifier)
            XCTAssertEqual(givenEmail, actualEmail)

            onComplete(Result.success(()))
        }

        let expect = expectation(description: "Expect to complete identify")
        customerIO.identify(identifier: givenIdentifier, onComplete: { result in
            expect.fulfill()
        }, email: givenEmail)

        waitForExpectations()
    }

    func test_identify_givenFailedAddCustomer_expectFailureResult() {
        identifyRepositoryMock.addOrUpdateCustomerClosure = { _, _, onComplete in
            onComplete(Result.failure(.httpError(.unsuccessfulStatusCode(500, message: ""))))
        }

        let expect = expectation(description: "Expect to complete identify")
        customerIO.identify(identifier: String.random) { result in
            guard case .failure(let error) = result else { return XCTFail() }
            guard case .httpError(let httpError) = error else { return XCTFail() }
            guard case .unsuccessfulStatusCode = httpError else { return XCTFail() }

            expect.fulfill()
        }

        waitForExpectations()
    }

    func test_identify_givenSuccessfullyAddCustomer_expectSuccessResult() {
        identifyRepositoryMock.addOrUpdateCustomerClosure = { _, _, onComplete in
            onComplete(Result.success(()))
        }

        let expect = expectation(description: "Expect to complete identify")
        customerIO.identify(identifier: String.random) { result in
            guard case .success = result else { return XCTFail() }

            expect.fulfill()
        }

        waitForExpectations()
    }
}
