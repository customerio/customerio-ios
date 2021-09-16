@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class IdentifyRepositoryTest: UnitTest {
    private var httpClientMock: HttpClientMock!
    private var keyValueStorageMock: KeyValueStorageMock!
    private var eventBusMock: EventBusMock!
    private var siteId: String!

    private var repository: IdentifyRepository!
    private var integrationRepository: IdentifyRepository!

    override func setUp() {
        super.setUp()

        httpClientMock = HttpClientMock()
        keyValueStorageMock = KeyValueStorageMock()
        eventBusMock = EventBusMock()
        siteId = String.random

        repository = CIOIdentifyRepository(httpClient: httpClientMock, keyValueStorage: keyValueStorageMock,
                                           jsonAdapter: jsonAdapter,
                                           siteId: siteId,
                                           eventBus: eventBusMock)
        integrationRepository = CIOIdentifyRepository(httpClient: httpClientMock, keyValueStorage: keyValueStorage,
                                                      jsonAdapter: jsonAdapter,
                                                      siteId: siteId,
                                                      eventBus: eventBusMock)
    }

    override func tearDown() {
        super.tearDown()
        integrationRepository.removeCustomer()
    }

    // MARK: addOrUpdateCustomer

    func test_addOrUpdateCustomer_expectCallHttpClientWithCorrectParams() {
        let givenIdentifier = String.random
        let givenBody = IdentifyRequestBody.random()

        httpClientMock.requestClosure = { params, onComplete in
            guard case .identifyCustomer(let actualIdentifier) = params.endpoint else { return XCTFail() }
            let actualBody: IdentifyRequestBody = self.jsonAdapter.fromJson(params.body!)!
            XCTAssertEqual(actualIdentifier, givenIdentifier)
            XCTAssertEqual(givenBody, actualBody)

            onComplete(Result.success(params.body!))
        }

        let expect = expectation(description: "Expect to complete")
        repository.addOrUpdateCustomer(identifier: givenIdentifier, body: givenBody, jsonEncoder: nil) { _ in
            expect.fulfill()
        }

        waitForExpectations()
    }

    func test_addOrUpdateCustomer_givenHttpFailure_expectDoNotSaveData_expectGetError() {
        httpClientMock.requestClosure = { params, onComplete in
            onComplete(Result.failure(HttpRequestError.unsuccessfulStatusCode(500, message: "")))
        }

        let expect = expectation(description: "Expect to complete")
        repository.addOrUpdateCustomer(identifier: String.random, body: ["": ""], jsonEncoder: nil) { result in
            guard case .failure(let actualError) = result else { return XCTFail() }
            guard case .http(let httpError) = actualError else { return XCTFail() }
            guard case .unsuccessfulStatusCode(let code, _) = httpError, code == 500 else { return XCTFail() }

            XCTAssertFalse(self.keyValueStorageMock.mockCalled)

            expect.fulfill()
        }

        waitForExpectations()
    }

    func test_addOrUpdateCustomer_givenHttpSuccess_expectSaveExpectedData() {
        let givenIdentifier = String.random

        httpClientMock.requestClosure = { params, onComplete in
            onComplete(Result.success(Data()))
        }

        let expect = expectation(description: "Expect to complete")
        integrationRepository
            .addOrUpdateCustomer(identifier: givenIdentifier, body: ["": ""], jsonEncoder: nil) { result in
                guard case .success = result else { return XCTFail() }

                XCTAssertEqual(self.keyValueStorage.string(siteId: self.siteId, forKey: .identifiedProfileId),
                               givenIdentifier)

                expect.fulfill()
            }

        waitForExpectations()
    }

    func test_addOrUpdateCustomer_givenCustomJsonEncoder_expectUseJsonEncoder() {
        let givenEncoder = JSONEncoder() // uses camelCase as our test
        let givenBody = Foo(firstName: "Dana")
        let expected = #"{"firstName":"Dana"}"#

        struct Foo: Codable {
            let firstName: String
        }

        httpClientMock.requestClosure = { _, onComplete in onComplete(Result.success(Data())) }

        let expect = expectation(description: "Expect to complete")
        integrationRepository.addOrUpdateCustomer(identifier: String.random, body: givenBody,
                                                  jsonEncoder: givenEncoder) { result in
            expect.fulfill()
        }

        waitForExpectations()

        XCTAssertNotEqual(jsonAdapter.toJson(givenBody)?.string,
                          expected) // make sure our custom JSONEncoder is different then SDK's
        XCTAssertEqual(httpClientMock.requestReceivedArguments?.params.body?.string, expected)
    }

    // MARK: removeCustomer

    func test_removeCustomer_givenNeverIdentifiedProfile_expectIgnoreRequest() {
        integrationRepository.removeCustomer()

        XCTAssertNil(keyValueStorage.string(siteId: siteId, forKey: .identifiedProfileId))
    }

    func test_removeCustomer_givenIdentifiedCustomer_expectCustomerRemoved() {
        let givenIdentifier = String.random

        httpClientMock.requestClosure = { params, onComplete in
            onComplete(Result.success(Data()))
        }

        let expect = expectation(description: "Expect to complete")
        integrationRepository
            .addOrUpdateCustomer(identifier: givenIdentifier, body: ["": ""], jsonEncoder: nil) { result in
                XCTAssertEqual(self.keyValueStorage.string(siteId: self.siteId, forKey: .identifiedProfileId),
                               givenIdentifier)

                self.integrationRepository.removeCustomer()

                XCTAssertNil(self.keyValueStorage.string(siteId: self.siteId, forKey: .identifiedProfileId))

                expect.fulfill()
            }

        waitForExpectations()
    }

    // MARK: trackEvent

    func test_trackEvent_expectCallHttpClientWithEmptyBodyNilTimestamp() {
        httpClientMock.requestClosure = { params, onComplete in
            onComplete(Result.success(Data()))
        }

        let givenIdentifier = String.random

        let expect = expectation(description: "Expect to complete")
        expect.expectedFulfillmentCount = 2
        integrationRepository
            .addOrUpdateCustomer(identifier: givenIdentifier, body: EmptyRequestBody(), jsonEncoder: nil) { result in
                XCTAssertEqual(self.integrationRepository.identifier, givenIdentifier)
                expect.fulfill()
            }

        let givenEventName = String.random
        httpClientMock.requestClosure = { params, onComplete in
            guard case .trackCustomerEvent(let actualIdentifier) = params.endpoint else { return XCTFail() }

            XCTAssertEqual(actualIdentifier, givenIdentifier)
            
            let actualBody: TrackRequestDecodable = self.jsonAdapter.fromJson(params.body!)!
            XCTAssertEqual(actualBody.name, givenEventName)
            XCTAssertEqual(actualBody.data, TrackEventData.blank())
            XCTAssertNil(actualBody.timestamp)

            onComplete(Result.success(params.body!))
        }

        integrationRepository.trackEvent(name: givenEventName, data: EmptyRequestBody(), timestamp: nil,
                                         jsonEncoder: nil) { _ in
            expect.fulfill()
        }

        waitForExpectations()

        XCTAssertEqual(httpClientMock.requestCallsCount, 2)
    }

    func test_trackEvent_expectCallHttpClientWithBodyAndNilTimestamp() {
        httpClientMock.requestClosure = { params, onComplete in
            onComplete(Result.success(Data()))
        }

        let givenIdentifier = String.random

        let expect = expectation(description: "Expect to complete")
        expect.expectedFulfillmentCount = 2
        integrationRepository
            .addOrUpdateCustomer(identifier: givenIdentifier, body: EmptyRequestBody(), jsonEncoder: nil) { result in
                XCTAssertEqual(self.integrationRepository.identifier, givenIdentifier)
                expect.fulfill()
            }

        let givenEventName = String.random
        let givenEventData = TrackEventData.random()

        httpClientMock.requestClosure = { params, onComplete in
            guard case .trackCustomerEvent(let actualIdentifier) = params.endpoint else { return XCTFail() }

            XCTAssertEqual(actualIdentifier, givenIdentifier)
            
            let actualBody: TrackRequestDecodable = self.jsonAdapter.fromJson(params.body!)!
            XCTAssertEqual(actualBody.name, givenEventName)
            XCTAssertEqual(actualBody.data, givenEventData)
            XCTAssertNil(actualBody.timestamp)

            onComplete(Result.success(params.body!))
        }

        integrationRepository
            .trackEvent(name: givenEventName, data: givenEventData, timestamp: nil, jsonEncoder: nil) { _ in
                expect.fulfill()
            }

        waitForExpectations()

        XCTAssertEqual(httpClientMock.requestCallsCount, 2)
    }

    func test_trackEvent_expectCallHttpClientWithBodyAndTimestamp() {
        httpClientMock.requestClosure = { params, onComplete in
            onComplete(Result.success(Data()))
        }

        let givenIdentifier = String.random

        let expect = expectation(description: "Expect to complete")
        expect.expectedFulfillmentCount = 2
        integrationRepository
            .addOrUpdateCustomer(identifier: givenIdentifier, body: EmptyRequestBody(), jsonEncoder: nil) { result in
                XCTAssertEqual(self.integrationRepository.identifier, givenIdentifier)
                expect.fulfill()
            }

        let givenEventName = String.random
        let givenEventData = TrackEventData.random()

        let givenTimestamp = Date(timeIntervalSince1970: 1631731924)

        httpClientMock.requestClosure = { params, onComplete in
            guard case .trackCustomerEvent(let actualIdentifier) = params.endpoint else { return XCTFail() }

            XCTAssertEqual(actualIdentifier, givenIdentifier)
            
            let actualBody: TrackRequestDecodable = self.jsonAdapter.fromJson(params.body!)!
            XCTAssertEqual(actualBody.name, givenEventName)
            XCTAssertEqual(actualBody.data, givenEventData)
            XCTAssertEqual(actualBody.timestamp, givenTimestamp)

            onComplete(Result.success(params.body!))
        }

        integrationRepository.trackEvent(name: givenEventName, data: givenEventData, timestamp: givenTimestamp,
                                         jsonEncoder: nil) { _ in
            expect.fulfill()
        }

        waitForExpectations()

        XCTAssertEqual(httpClientMock.requestCallsCount, 2)
    }

    func test_trackEvent_givenNoIdentifiedCustomer_ExpectFailure() {
        httpClientMock.requestClosure = { params, onComplete in
            onComplete(Result.success(Data()))
        }

        let expect = expectation(description: "Expect to complete")

        integrationRepository.trackEvent(name: String.random, data: EmptyRequestBody(), timestamp: nil,
                                         jsonEncoder: nil) { result in
            guard case .failure(let actualError) = result else { return XCTFail() }
            guard case .noCustomerIdentified = actualError else { return XCTFail() }

            expect.fulfill()
        }

        waitForExpectations()
    }

    func test_trackEvent_givenHttpFailure_expectGetError() {
        httpClientMock.requestClosure = { params, onComplete in
            onComplete(Result.success(Data()))
        }

        let givenIdentifier = String.random

        let expect = expectation(description: "Expect to complete")
        expect.expectedFulfillmentCount = 2
        integrationRepository
            .addOrUpdateCustomer(identifier: givenIdentifier, body: EmptyRequestBody(), jsonEncoder: nil) { result in
                XCTAssertEqual(self.integrationRepository.identifier, givenIdentifier)
                expect.fulfill()
            }

        httpClientMock.requestClosure = { params, onComplete in
            onComplete(Result.failure(HttpRequestError.unsuccessfulStatusCode(500, message: "")))
        }

        integrationRepository.trackEvent(name: String.random, data: EmptyRequestBody(), timestamp: nil,
                                         jsonEncoder: nil) { result in
            guard case .failure(let actualError) = result else { return XCTFail() }
            guard case .http(let httpError) = actualError else { return XCTFail() }
            guard case .unsuccessfulStatusCode(let code, _) = httpError, code == 500 else { return XCTFail() }

            expect.fulfill()
        }

        waitForExpectations()
    }
}
