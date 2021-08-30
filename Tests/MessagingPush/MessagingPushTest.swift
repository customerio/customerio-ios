@testable import CioTracking
@testable import CioMessagingPush
import Foundation
import SharedTests
import XCTest

class MessagingPushTest: UnitTest {
    private var messagingPush: MessagingPush!

    private var identifyRepositoryMock: IdentifyRepositoryMock!
    
    private var httpClientMock: HttpClientMock!
    private var keyValueStorageMock: KeyValueStorageMock!

    override func setUp() {
        super.setUp()

        httpClientMock = HttpClientMock()
        keyValueStorageMock = KeyValueStorageMock()
        identifyRepositoryMock = IdentifyRepositoryMock()

        let customerIO = CustomerIO(credentialsStore: nil, sdkConfig: SdkConfig(),
                                identifyRepository: identifyRepositoryMock, keyValueStorage: nil)
        
        messagingPush = MessagingPush(customerIO: customerIO, httpClient: httpClientMock, keyValueStorage: keyValueStorageMock)
    }

    // MARK: registerDevice

    func test_registerDeviceToken_expectFailIfNotIdentified() {
        let token = String.random
        
        let expect = expectation(description: "Expect to fail to register device token")
        self.messagingPush.registerDeviceToken(deviceToken: token) { result in
            guard case .failure(let error) = result else { return XCTFail() }
            guard case .notInitialized = error else { return XCTFail() }
            expect.fulfill()
        }
        
        waitForExpectations()
    }

//    func test_sharedInstance_givenInitializeBefore_expectLoadCredentialsOnInit() {
//        let givenSiteId = String.random
//
//        // First, set the credentials on the shared instance
//        CustomerIO.initialize(siteId: givenSiteId, apiKey: String.random, region: Region.EU)
//        // next, create an instance of the shared instance and see if credentials loads
//        var instance: CustomerIO!
//        instance = CustomerIO()
//        XCTAssertNotNil(instance.credentials)
//        instance = nil // try to remove instance from memory simulating app removed from memory
//        XCTAssertNil(instance)
//
//        instance = CustomerIO()
//        XCTAssertNotNil(instance.credentials)
//        XCTAssertEqual(instance.credentials?.siteId, givenSiteId)
//    }

    // MARK: config

//    func test_config_sharedInstance_givenModifyConfig_expectSetConfigOnInstance() {
////        let givenTrackingApiUrl = String.random
////
////        XCTAssertNotEqual(CustomerIO.instance.sdkConfig.trackingApiUrl, givenTrackingApiUrl)
////
////        CustomerIO.config {
////            $0.trackingApiUrl = givenTrackingApiUrl
////        }
////
////        XCTAssertEqual(CustomerIO.instance.sdkConfig.trackingApiUrl, givenTrackingApiUrl)
//    }
}
