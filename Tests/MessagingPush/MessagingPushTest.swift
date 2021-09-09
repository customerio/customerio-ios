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
        
        messagingPush = MessagingPush(customerIO: mockCustomerIO, httpClient: httpClientMock, keyValueStorage: DITracking.shared.keyValueStorage)
    }

    // MARK: registerDeviceToken

    func test_registerDeviceToken_expectFailIfNotIdentified() {
 
        let expect = expectation(description: "Expect to fail to register device token")
        self.messagingPush.registerDeviceToken(deviceToken: String.random.data!) { result in
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
        
        mockCustomerIO.setIdentifier(identifier: String.random, onComplete: { result in
            guard case .success = result else { return XCTFail() }
            XCTAssertNotNil(self.mockCustomerIO.identifier)
        })
        
        httpClientMock.requestClosure = { params, onComplete in
            onComplete(Result.success(Data()))
        }
        
        let actualToken = String.random.data!
        
        let expect = expectation(description: "Expect to persist token")
        self.messagingPush.registerDeviceToken(deviceToken: actualToken) { result in
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
    
    func test_deleteDeviceToken_expectFailIfNotIdentified() {
                
        httpClientMock.requestClosure = { params, onComplete in
            onComplete(Result.success(Data()))
        }
        
        let expect = expectation(description: "Expect to fail to delete device token")
        self.messagingPush.deleteDeviceToken() { result in
            guard case .failure(let error) = result else { return XCTFail() }
            guard case .noCustomerIdentified = error else { return XCTFail() }
            expect.fulfill()
        }

        waitForExpectations()
    }
    
    func test_deleteDeviceToken_expectFailIfNoToken() {
        
        identifyRepositoryMock.setIdentifierClosure = { identifier in
            self.identifyRepositoryMock.identifier = identifier
        }
        
        mockCustomerIO.setIdentifier(identifier: String.random, onComplete: { result in
            guard case .success = result else { return XCTFail() }
            XCTAssertNotNil(self.mockCustomerIO.identifier)
        })
                
        httpClientMock.requestClosure = { params, onComplete in
            onComplete(Result.success(Data()))
        }
        
        let expect = expectation(description: "Expect to fail to delete device token")
        self.messagingPush.deleteDeviceToken() { result in
            guard case .failure(let error) = result else { return XCTFail() }
            guard case .deviceNotRegistered = error else { return XCTFail() }
            expect.fulfill()
        }

        waitForExpectations()
    }
    
    func test_deleteDeviceToken_givenHttpSuccess_expectClearToken() {
        
        identifyRepositoryMock.setIdentifierClosure = { identifier in
            self.identifyRepositoryMock.identifier = identifier
        }
        
        mockCustomerIO.setIdentifier(identifier: String.random, onComplete: { result in
            guard case .success = result else { return XCTFail() }
            XCTAssertNotNil(self.mockCustomerIO.identifier)
        })
        
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
