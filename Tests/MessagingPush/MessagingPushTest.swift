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
    
    private func pushSetup() -> MessagingPush{
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
            guard case .success = result else {  return XCTFail() }
            XCTAssertEqual(cio.identifier, identifier)
        }
        
        return MessagingPush(customerIO: cio, httpClient: httpClientMock, jsonAdapter: jsonAdapter)
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
        
        XCTAssertFalse(httpClientMock.requestCalled)
    }
    
    func test_registerDeviceToken_givenHttpSuccess_expectSaveExpectedData() {
        
        let push = pushSetup()

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
        
        XCTAssertTrue(httpClientMock.requestCalled)
    }
    
    func test_registerDeviceToken_givenHttpFailure_expectNilDeviceToken() {
        
        let push = pushSetup()
        
        httpClientMock.requestClosure = { params, onComplete in
            onComplete(Result.failure(HttpRequestError.unsuccessfulStatusCode(500, message: "")))
        }

        let actualToken = String.random.data!
        
        let expect = expectation(description: "Expect to persist token")
        push.registerDeviceToken(actualToken) { result in
            guard case .failure(let actualError) = result else { return XCTFail() }
            guard case .http(let httpError) = actualError else { return XCTFail() }
            guard case .unsuccessfulStatusCode(let code, _) = httpError, code == 500 else { return XCTFail() }
            expect.fulfill()
        }
    
        waitForExpectations()
        
        XCTAssertNil(push.deviceToken)
        XCTAssertTrue(httpClientMock.requestCalled)
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
        
        XCTAssertFalse(httpClientMock.requestCalled)
    }
    
    func test_deleteDeviceToken_expectSuccessIfNotIdentified() {

        httpClientMock.requestClosure = { params, onComplete in
            onComplete(Result.success(Data()))
        }
        
        let expect = expectation(description: "Expect delete to succeed if there is not token")
        self.messagingPush.deleteDeviceToken() { result in
            guard case .success = result else { return XCTFail() }
            expect.fulfill()
        }

        waitForExpectations()
        
        XCTAssertFalse(httpClientMock.requestCalled)
    }
    
    func test_deleteDeviceToken_givenHttpSuccess_expectClearToken() {
        
        let push = pushSetup()
        
        httpClientMock.requestClosure = { params, onComplete in
            onComplete(Result.success(Data()))
        }
        
        push.deviceToken = String.random.data!
        
        let expect = expectation(description: "Expect to clear token in memory")
        push.deleteDeviceToken() { result in
            guard case .success = result else { return XCTFail() }
            expect.fulfill()
        }
        
        XCTAssertNil(push.deviceToken)

        waitForExpectations()
        
        XCTAssertTrue(httpClientMock.requestCalled)
    }
    
    func test_deleteDeviceToken_givenHttpFailure_expectTokenNotCleared() {
        
        let push = pushSetup()
        
        httpClientMock.requestClosure = { params, onComplete in
            onComplete(Result.failure(HttpRequestError.unsuccessfulStatusCode(500, message: "")))
        }
        
        push.deviceToken = String.random.data!
        
        let expect = expectation(description: "Expect request to fail")
        push.deleteDeviceToken() { result in
            guard case .failure(let actualError) = result else { return XCTFail() }
            guard case .http(let httpError) = actualError else { return XCTFail() }
            guard case .unsuccessfulStatusCode(let code, _) = httpError, code == 500 else { return XCTFail() }
            expect.fulfill()
        }
        
        waitForExpectations()
        
        XCTAssertNotNil(push.deviceToken)
        XCTAssertTrue(httpClientMock.requestCalled)
    }
    
    // MARK: deinit
    
    func test_givenNilObject_expectDeinit() {
      var messagingPush: MessagingPush? = MessagingPush(customerIO: mockCustomerIO)

      messagingPush = nil

        XCTAssertNil(messagingPush)
    }
}
