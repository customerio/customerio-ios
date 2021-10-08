@testable import CioMessagingPush
@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class MessagingPushImplementationTest: UnitTest {
    private var mockCustomerIO: CustomerIOInstanceMock!
    private var messagingPush: MessagingPushImplementation!

    private var identifyRepositoryMock: IdentifyRepository!
    private var eventBusMock: EventBusMock!
    private var httpClientMock: HttpClientMock!
    private var profileStoreMock: ProfileStoreMock!

    override func setUp() {
        super.setUp()

        httpClientMock = HttpClientMock()
        diGraph.override(.httpClient, value: httpClientMock, forType: HttpClient.self)

        identifyRepositoryMock = IdentifyRepositoryMock()
        diGraph.override(.identifyRepository, value: identifyRepositoryMock, forType: IdentifyRepository.self)

        eventBusMock = EventBusMock()
        diGraph.override(.eventBus, value: eventBusMock, forType: EventBus.self)

        profileStoreMock = ProfileStoreMock()
        diGraph.override(.profileStore, value: profileStoreMock, forType: ProfileStore.self)

        mockCustomerIO = CustomerIOInstanceMock()
        mockCustomerIO.siteId = testSiteId

        messagingPush = MessagingPushImplementation(httpClient: httpClientMock, jsonAdapter: jsonAdapter,
                                                    eventBus: eventBusMock, profileStore: profileStoreMock)
    }

    // MARK: registerDeviceToken

    func test_registerDeviceToken_expectFailIfNoCustomerIdentified() {
        profileStoreMock.identifier = nil

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
        profileStoreMock.identifier = String.random
        let actualToken = String.random

        httpClientMock.requestClosure = { params, onComplete in
            onComplete(.success(Data()))
        }

        let expect = expectation(description: "Expect to persist token")
        messagingPush.registerDeviceToken(actualToken) { result in
            guard case .success = result else { return XCTFail() }
            expect.fulfill()
        }

        waitForExpectations()

        guard let storedToken = messagingPush.deviceToken else { return XCTFail() }
        XCTAssertEqual(storedToken, actualToken)
        XCTAssertTrue(httpClientMock.requestCalled)
    }

    func test_registerDeviceToken_givenHttpFailure_expectNilDeviceToken() {
        profileStoreMock.identifier = String.random

        httpClientMock.requestClosure = { params, onComplete in
            onComplete(Result.failure(HttpRequestError.unsuccessfulStatusCode(500, apiMessage: "")))
        }

        let actualToken = String.random

        let expect = expectation(description: "Expect to persist token")
        messagingPush.registerDeviceToken(actualToken) { result in
            guard case .failure(let actualError) = result else { return XCTFail() }
            guard case .http(let httpError) = actualError else { return XCTFail() }
            guard case .unsuccessfulStatusCode(let code, _) = httpError, code == 500 else { return XCTFail() }
            expect.fulfill()
        }

        waitForExpectations()

        XCTAssertNil(messagingPush.deviceToken)
        XCTAssertTrue(httpClientMock.requestCalled)
    }

    // MARK: deleteDeviceToken

    func test_deleteDeviceToken_expectSuccessIfNoToken() {
        messagingPush.deviceToken = nil

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
        profileStoreMock.identifier = nil

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
        profileStoreMock.identifier = String.random
        messagingPush.deviceToken = String.random

        httpClientMock.requestClosure = { params, onComplete in
            onComplete(Result.success(Data()))
        }

        let expect = expectation(description: "Expect to clear token in memory")
        messagingPush.deleteDeviceToken { result in
            guard case .success = result else { return XCTFail() }
            expect.fulfill()
        }

        waitForExpectations()

        XCTAssertNil(messagingPush.deviceToken)
        XCTAssertTrue(httpClientMock.requestCalled)
    }

    func test_deleteDeviceToken_givenHttpFailure_expectTokenNotCleared() {
        profileStoreMock.identifier = String.random
        messagingPush.deviceToken = String.random

        httpClientMock.requestClosure = { params, onComplete in
            onComplete(Result.failure(HttpRequestError.unsuccessfulStatusCode(500, apiMessage: "")))
        }

        let expect = expectation(description: "Expect request to fail")
        messagingPush.deleteDeviceToken { result in
            guard case .failure(let actualError) = result else { return XCTFail() }
            guard case .http(let httpError) = actualError else { return XCTFail() }
            guard case .unsuccessfulStatusCode(let code, _) = httpError, code == 500 else { return XCTFail() }
            expect.fulfill()
        }

        waitForExpectations()

        XCTAssertNotNil(messagingPush.deviceToken)
        XCTAssertTrue(httpClientMock.requestCalled)
    }

    // MARK: trackMetric

    func test_trackMetric_givenHttpSuccess_expectSuccess() {
        httpClientMock.requestClosure = { params, onComplete in
            onComplete(Result.success(Data()))
        }

        let expect = expectation(description: "Expect trackMetric to succeed")
        messagingPush.trackMetric(deliveryID: String.random, event: .delivered, deviceToken: String.random) { result in
            guard case .success = result else { return XCTFail() }
            expect.fulfill()
        }

        waitForExpectations()

        XCTAssertTrue(httpClientMock.requestCalled)
    }

    func test_trackMetric_givenHttpFailure_expectFailure() {
        httpClientMock.requestClosure = { params, onComplete in
            onComplete(Result.failure(HttpRequestError.unsuccessfulStatusCode(500, apiMessage: "")))
        }

        let expect = expectation(description: "Expect trackMetric to fail")
        messagingPush.trackMetric(deliveryID: String.random, event: .delivered, deviceToken: String.random) { result in
            guard case .failure(let actualError) = result else { return XCTFail() }
            guard case .http(let httpError) = actualError else { return XCTFail() }
            guard case .unsuccessfulStatusCode(let code, _) = httpError, code == 500 else { return XCTFail() }
            expect.fulfill()
        }

        waitForExpectations()

        XCTAssertTrue(httpClientMock.requestCalled)
    }
}
