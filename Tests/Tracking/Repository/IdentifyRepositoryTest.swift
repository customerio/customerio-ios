@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class IdentifyRepositoryTest: UnitTest {
    private var httpClientMock: HttpClientMock!
    private var keyValueStorageMock: KeyValueStorageMock!
    private var siteId: String!

    private var repository: IdentifyRepository!
    private var integrationRepository: IdentifyRepository!

    override func setUp() {
        super.setUp()

        httpClientMock = HttpClientMock()
        keyValueStorageMock = KeyValueStorageMock()
        siteId = String.random

        repository = CIOIdentifyRepository(httpClient: httpClientMock, keyValueStorage: keyValueStorageMock,
                                           jsonAdapter: jsonAdapter,
                                           siteId: siteId)
        integrationRepository = CIOIdentifyRepository(httpClient: httpClientMock, keyValueStorage: keyValueStorage,
                                                      jsonAdapter: jsonAdapter,
                                                      siteId: siteId)
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
}
