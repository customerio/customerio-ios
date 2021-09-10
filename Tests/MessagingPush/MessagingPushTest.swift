@testable import CioTracking
@testable import CioMessagingPush
import Foundation
import SharedTests
import XCTest

class MessagingPushTest: UnitTest {
    private var mockCustomerIO: CustomerIO!
    private var messagingPush: MessagingPush!

    private var identifyRepositoryMock: IdentifyRepository!
    
    private var httpClientMock: HttpClientMock!

    override func setUp() {
        super.setUp()

        httpClientMock = HttpClientMock()
        identifyRepositoryMock = IdentifyRepositoryMock()

        mockCustomerIO = CustomerIO(credentialsStore: SdkCredentialsStoreMock(), sdkConfig: SdkConfig(), identifyRepository: identifyRepositoryMock, keyValueStorage: nil)
        
        mockCustomerIO.credentials = SdkCredentials(siteId: String.random,
                                         apiKey: String.random,
                                         region: Region.EU)
        
        messagingPush = MessagingPush(customerIO: mockCustomerIO, httpClient: httpClientMock, jsonAdapter: jsonAdapter)
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
        
        let identifyRepository = CIOIdentifyRepository(httpClient: httpClientMock, keyValueStorage: DITracking.shared.keyValueStorage, jsonAdapter: jsonAdapter, siteId: String.random)
        let cio = CustomerIO(credentialsStore: SdkCredentialsStoreMock(), sdkConfig: SdkConfig(), identifyRepository: identifyRepository, keyValueStorage: nil)
        
        cio.credentials = SdkCredentials(siteId: String.random,
                                         apiKey: String.random,
                                         region: Region.EU)
    
        httpClientMock.requestClosure = { params, onComplete in
            onComplete(Result.success(Data()))
        }
        
        let identifier: String? = String.random

    
        cio.identify(identifier: identifier!) { result in
            guard case .success = result else { print(result); return XCTFail() }
            XCTAssertEqual(cio.identifier, identifier)
        }
        
        let push = MessagingPush(customerIO: cio, httpClient: httpClientMock, jsonAdapter: jsonAdapter)
        

        let actualToken = String.random.data!
        
        let expect = expectation(description: "Expect to persist token")
        push.registerDeviceToken(actualToken) { result in
            guard case .success = result else { return XCTFail() }
            expect.fulfill()
        }
        
        guard let storedToken = push.deviceToken else {
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
