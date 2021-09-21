@testable import CioMessagingPush
@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class MessagingPushTest: UnitTest {
    private var mockCustomerIO: CustomerIO!
    private var messagingPush: MessagingPush!

    private var identifyRepositoryMock: IdentifyRepository!
    private var eventBusMock: EventBusMock!

    private var httpClientMock: HttpClientMock!

    override func setUp() {
        super.setUp()

        httpClientMock = HttpClientMock()
        identifyRepositoryMock = IdentifyRepositoryMock()
        eventBusMock = EventBusMock()

        mockCustomerIO = CustomerIO(credentialsStore: SdkCredentialsStoreMock(), sdkConfig: SdkConfig(),
                                    identifyRepository: identifyRepositoryMock, keyValueStorage: nil)

        mockCustomerIO.credentials = SdkCredentials(siteId: String.random,
                                                    apiKey: String.random,
                                                    region: Region.EU)

        messagingPush = MessagingPush(customerIO: mockCustomerIO, httpClient: httpClientMock, jsonAdapter: jsonAdapter,
                                      eventBus: eventBusMock)
    }

    private func pushSetup() -> MessagingPush {
        let identifyRepository = CIOIdentifyRepository(httpClient: httpClientMock,
                                                       keyValueStorage: DITracking.shared.keyValueStorage,
                                                       jsonAdapter: jsonAdapter, siteId: String.random,
                                                       eventBus: EventBusMock())
        let cio = CustomerIO(credentialsStore: SdkCredentialsStoreMock(), sdkConfig: SdkConfig(),
                             identifyRepository: identifyRepository, keyValueStorage: nil)

        cio.credentials = SdkCredentials(siteId: String.random,
                                         apiKey: String.random,
                                         region: Region.EU)

        httpClientMock.requestClosure = { params, onComplete in
            onComplete(Result.success(Data()))
        }

        let identifier: String? = String.random

        cio.identify(identifier: identifier!) { result in
            guard case .success = result else { return XCTFail() }
            XCTAssertEqual(cio.identifier, identifier)
        }

        return MessagingPush(customerIO: cio, httpClient: httpClientMock, jsonAdapter: jsonAdapter,
                             eventBus: eventBusMock)
    }

    // MARK: registerDeviceToken

    func test_registerDeviceToken_expectFailIfNoCustomerIdentified() {
        let expect = expectation(description: "Expect to fail to register device token")
        messagingPush.registerDeviceToken(String.random) { result in
            guard case .failure(let error) = result else { return XCTFail() }
            guard case .noCustomerIdentified = error else { return XCTFail() }
            expect.fulfill()
        }

        waitForExpectations()

        XCTAssertFalse(httpClientMock.requestCalled)
    }

    func test_registerDeviceToken_givenHttpSuccess_expectSaveExpectedData() {
        let push = pushSetup()

        let actualToken = String.random

        let expect = expectation(description: "Expect to persist token")
        push.registerDeviceToken(actualToken) { result in
            guard case .success = result else { return XCTFail() }
            expect.fulfill()
        }

        waitForExpectations()

        guard let storedToken = push.deviceToken else { return XCTFail() }
        XCTAssertEqual(storedToken, actualToken)
        XCTAssertTrue(httpClientMock.requestCalled)
    }

    func test_registerDeviceToken_givenHttpFailure_expectNilDeviceToken() {
        let push = pushSetup()

        httpClientMock.requestClosure = { params, onComplete in
            onComplete(Result.failure(HttpRequestError.unsuccessfulStatusCode(500, message: "")))
        }

        let actualToken = String.random

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
        messagingPush.deleteDeviceToken { result in
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
        messagingPush.deleteDeviceToken { result in
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

        push.deviceToken = String.random

        let expect = expectation(description: "Expect to clear token in memory")
        push.deleteDeviceToken { result in
            guard case .success = result else { return XCTFail() }
            expect.fulfill()
        }

        waitForExpectations()

        XCTAssertNil(push.deviceToken)
        XCTAssertTrue(httpClientMock.requestCalled)
    }

    func test_deleteDeviceToken_givenHttpFailure_expectTokenNotCleared() {
        let push = pushSetup()

        httpClientMock.requestClosure = { params, onComplete in
            onComplete(Result.failure(HttpRequestError.unsuccessfulStatusCode(500, message: "")))
        }

        push.deviceToken = String.random

        let expect = expectation(description: "Expect request to fail")
        push.deleteDeviceToken { result in
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
