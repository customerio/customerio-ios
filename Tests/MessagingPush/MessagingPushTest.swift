@testable import CioTracking
@testable import CioMessagingPush
import Foundation
import SharedTests
import XCTest

class MessagingPushTest: UnitTest {
    private var customerIO: CustomerIO!
    private var messagingPush: MessagingPush!

    private var identifyRepositoryMock: IdentifyRepositoryMock!
    
    private var httpClientMock: HttpClientMock!

    override func setUp() {
        super.setUp()

        httpClientMock = HttpClientMock()
        identifyRepositoryMock = IdentifyRepositoryMock()

        customerIO = CustomerIO(credentialsStore: nil, sdkConfig: SdkConfig(), identifyRepository: identifyRepositoryMock,
                                keyValueStorage: nil)
        
        customerIO.setCredentials(siteId: String.random, apiKey: String.random, region: Region.EU)
        
        messagingPush = MessagingPush(customerIO: customerIO, httpClient: httpClientMock, keyValueStorage: DITracking.shared.keyValueStorage)
    }

    // MARK: registerDevice

    func test_registerDeviceToken_expectFailIfNotIdentified() {
        let token = Data(String.random.utf8)
        
        let expect = expectation(description: "Expect to fail to register device token")
        self.messagingPush.registerDeviceToken(deviceToken: token) { result in
            guard case .failure(let error) = result else { return XCTFail() }
            guard case .notInitialized = error else { return XCTFail() }
            expect.fulfill()
        }
        
        waitForExpectations()
    }
    
    func test_registerDeviceToken_givenHttpSuccess_expectSaveExpectedData() {
        
        identifyRepositoryMock.setIdentifierClosure = { identifier in
            self.identifyRepositoryMock.identifier = identifier
        }
        
        customerIO.setIdentifier(identifier: String.random, onComplete: { result in
            guard case .success = result else { return XCTFail() }
            XCTAssertNotNil(self.customerIO.identifier)
        })
        
        httpClientMock.requestClosure = { params, onComplete in
            onComplete(Result.success(Data()))
        }
        
        let token = Data(String.random.utf8)
        
        let expect = expectation(description: "Expect to persist token")
        self.messagingPush.registerDeviceToken(deviceToken: token) { result in
            guard case .success = result else { return XCTFail() }
            
            XCTAssertNotNil(self.messagingPush.deviceToken)
            expect.fulfill()
        }

        waitForExpectations()
    }
}
