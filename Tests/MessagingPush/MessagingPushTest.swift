@testable import CioTracking
@testable import CioMessagingPush
import Foundation
import SharedTests
import XCTest

class MessagingPushTest: UnitTest {
    private var mockCustomerIO: CustomerIO!
    private var messagingPush: MessagingPush!

    private var identifyRepositoryMock: IdentifyRepositoryMock!
    
    private var httpClientMock: HttpClientMock!

    override func setUp() {
        super.setUp()

        httpClientMock = HttpClientMock()
        identifyRepositoryMock = IdentifyRepositoryMock()

        mockCustomerIO = CustomerIO(credentialsStore: nil, sdkConfig: SdkConfig(), identifyRepository: identifyRepositoryMock,
                                keyValueStorage: nil)
        
        mockCustomerIO.setCredentials(siteId: String.random, apiKey: String.random, region: Region.EU)
        
        messagingPush = MessagingPush(customerIO: mockCustomerIO, httpClient: httpClientMock, keyValueStorage: DITracking.shared.keyValueStorage, jsonAdapter: jsonAdapter)
    }

    // MARK: registerDeviceToken

    func test_registerDeviceToken_expectFailIfNoCustomerIdentified() {
 
        let expect = expectation(description: "Expect to fail to register device token")
        self.messagingPush.registerDeviceToken(String.random.data!) { result in
            guard case .failure(let error) = result else { return XCTFail() }
            guard case .noCustomerIdentified = error else { return XCTFail() }
            expect.fulfill()
        }
        
        waitForExpectations()
    }
    
    func test_registerDeviceToken_givenHttpSuccess_expectSaveExpectedData() {

        // XXX: fixme
        
        httpClientMock.requestClosure = { params, onComplete in
            onComplete(Result.success(Data()))
        }
        
        let actualToken = String.random.data!
        
        let expect = expectation(description: "Expect to persist token")
        self.messagingPush.registerDeviceToken(actualToken) { result in
            guard case .success = result else { return XCTFail() }
            expect.fulfill()
        }
        
        guard let storedToken = self.messagingPush.deviceToken else {
            return XCTFail()
        }
        
        XCTAssertEqual(storedToken, actualToken)

        waitForExpectations()
    }
    
    // MARK: deleteDeviceToken
    
    func test_deleteDeviceToken_expectSuccessIfNoToken() {
                
        httpClientMock.requestClosure = { params, onComplete in
            onComplete(Result.success(Data()))
        }
        
        let expect = expectation(description: "Expect delete to succeed if there is no identified customer")
        self.messagingPush.deleteDeviceToken() { result in
            guard case .success = result else { return XCTFail() }
            expect.fulfill()
        }

        waitForExpectations()
    }
    
    func test_deleteDeviceToken_expectSuccessIfNotIdentified() {
        
        // XXX: todo
                
        httpClientMock.requestClosure = { params, onComplete in
            onComplete(Result.success(Data()))
        }
        
        let expect = expectation(description: "Expect delete to succeed if there is not token")
        self.messagingPush.deleteDeviceToken() { result in
            guard case .success = result else { return XCTFail() }
            expect.fulfill()
        }

        waitForExpectations()
    }
    
    func test_deleteDeviceToken_givenHttpSuccess_expectClearToken() {
        
        httpClientMock.requestClosure = { params, onComplete in
            onComplete(Result.success(Data()))
        }
        
        self.messagingPush.deviceToken = String.random.data!
        
        let expect = expectation(description: "Expect to clear token in memory")
        self.messagingPush.deleteDeviceToken() { result in
            guard case .success = result else { return XCTFail() }
            expect.fulfill()
        }
        
        XCTAssertNil(self.messagingPush.deviceToken)

        waitForExpectations()
    }
    
    // MARK: deinit
    
    func test_givenNilObject_expectDeinit() {
      var messagingPush: MessagingPush? = MessagingPush(customerIO: mockCustomerIO)

      messagingPush = nil

        XCTAssertNil(messagingPush)
    }
}
