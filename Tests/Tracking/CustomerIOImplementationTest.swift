@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class CustomerIOImplementationTest: UnitTest {
    private var customerIO: CustomerIOImplementation!

    private var identifyRepositoryMock = IdentifyRepositoryMock()

    override func setUp() {
        super.setUp()

        diGraph.override(.identifyRepository, value: identifyRepositoryMock, forType: IdentifyRepository.self)

        customerIO = CustomerIOImplementation(siteId: diGraph.siteId)
    }

    // MARK: config

    func test_config_givenModifyConfig_expectSetConfigOnInstance() {
        let givenTrackingApiUrl = String.random

        customerIO.config {
            $0.trackingApiUrl = givenTrackingApiUrl
        }

        let sdkConfig = diGraph.sdkConfigStore.config

        XCTAssertEqual(sdkConfig.trackingApiUrl, givenTrackingApiUrl)
    }

    // MARK: identify

    // testing `identify()` with request body. Will make an integration test for all `identify()` functions
    // but copy/paste identify unit tests not needed since only 1 function has logic in it.
    //
    // NOTE: At this time, the `CustomerIOHttpTest` is that integration test. After refactoring the code
    // to make the DI graph work as intended and the http request runner is in the graph we can make
    // integration tests with a mocked request runner.

    func test_identify_expectCallRepository() {
        let givenIdentifier = String.random
        let givenBody = IdentifyRequestBody.random()

        identifyRepositoryMock.addOrUpdateCustomerClosure = { actualIdentifier, actualBody, _, onComplete in
            XCTAssertEqual(givenIdentifier, actualIdentifier)
            XCTAssertEqual(givenBody, actualBody.value as! IdentifyRequestBody)

            onComplete(Result.success(()))
        }

        let expect = expectation(description: "Expect to complete identify")
        customerIO.identify(identifier: givenIdentifier, body: givenBody) { result in
            expect.fulfill()
        }

        waitForExpectations()
    }

    func test_identify_givenFailedAddCustomer_expectFailureResult() {
        identifyRepositoryMock.addOrUpdateCustomerClosure = { _, _, _, onComplete in
            onComplete(Result.failure(.http(.unsuccessfulStatusCode(500, apiMessage: ""))))
        }

        let expect = expectation(description: "Expect to complete identify")
        expect.expectedFulfillmentCount = 2
        customerIO.identify(identifier: String.random) { result in
            guard case .failure(let error) = result else { return XCTFail() }
            guard case .http(let httpError) = error else { return XCTFail() }
            guard case .unsuccessfulStatusCode = httpError else { return XCTFail() }

            expect.fulfill()
        }
        customerIO.identify(identifier: String.random, body: IdentifyRequestBody.random()) { result in
            guard case .failure(let error) = result else { return XCTFail() }
            guard case .http(let httpError) = error else { return XCTFail() }
            guard case .unsuccessfulStatusCode = httpError else { return XCTFail() }

            expect.fulfill()
        }

        waitForExpectations()
    }

    func test_identify_givenSuccessfullyAddCustomer_expectSuccessResult() {
        identifyRepositoryMock.addOrUpdateCustomerClosure = { _, _, _, onComplete in
            onComplete(Result.success(()))
        }

        let expect = expectation(description: "Expect to complete identify")
        expect.expectedFulfillmentCount = 2
        customerIO.identify(identifier: String.random) { result in
            guard case .success = result else { return XCTFail() }

            expect.fulfill()
        }

        customerIO.identify(identifier: String.random, body: IdentifyRequestBody.random()) { result in
            guard case .success = result else { return XCTFail() }

            expect.fulfill()
        }

        waitForExpectations()
    }

    // MARK: track

    func test_track_expectCallRepository() {
        let givenEventName = String.random
        let givenEventData = TrackEventData.random()

        identifyRepositoryMock.trackEventClosure = { actualEventName, actualEventData, _, _, onComplete in
            XCTAssertEqual(givenEventName, actualEventName)
            XCTAssertEqual(givenEventData, actualEventData.value as! TrackEventData)

            onComplete(Result.success(()))
        }

        let expect = expectation(description: "Expect to complete track")
        customerIO.track(name: givenEventName, data: givenEventData) { result in
            expect.fulfill()
        }

        waitForExpectations()

        XCTAssertEqual(identifyRepositoryMock.trackEventCallsCount, 1)
    }

    func test_track_givenFailedTrackEvent_expectFailureResult() {
        identifyRepositoryMock.trackEventClosure = { _, _, _, _, onComplete in
            onComplete(Result.failure(.http(.unsuccessfulStatusCode(500, apiMessage: ""))))
        }

        let expect = expectation(description: "Expect to complete track")
        expect.expectedFulfillmentCount = 2
        customerIO.track(name: String.random) { result in
            guard case .failure(let error) = result else { return XCTFail() }
            guard case .http(let httpError) = error else { return XCTFail() }
            guard case .unsuccessfulStatusCode = httpError else { return XCTFail() }

            expect.fulfill()
        }
        customerIO.track(name: String.random, data: TrackEventData.random()) { result in
            guard case .failure(let error) = result else { return XCTFail() }
            guard case .http(let httpError) = error else { return XCTFail() }
            guard case .unsuccessfulStatusCode = httpError else { return XCTFail() }

            expect.fulfill()
        }

        waitForExpectations()
    }

    func test_track_givenSuccessfullyAddCustomer_expectSuccessResult() {
        identifyRepositoryMock.trackEventClosure = { _, _, _, _, onComplete in
            onComplete(Result.success(()))
        }

        let expect = expectation(description: "Expect to complete identify")
        expect.expectedFulfillmentCount = 2
        customerIO.track(name: String.random) { result in
            guard case .success = result else { return XCTFail() }

            expect.fulfill()
        }

        customerIO.track(name: String.random, data: TrackEventData.random()) { result in
            guard case .success = result else { return XCTFail() }

            expect.fulfill()
        }

        waitForExpectations()

        XCTAssertEqual(identifyRepositoryMock.trackEventCallsCount, 2)
    }
    
    // MARK: screen
    
    func test_screen_givenFailedScreen_expectFailureResult() {
        identifyRepositoryMock.screenClosure = { _, _, _, _, onComplete in
            onComplete(Result.failure(.http(.unsuccessfulStatusCode(500, apiMessage: ""))))
        }

        let expect = expectation(description: "Expect to complete screen")
        expect.expectedFulfillmentCount = 2
        customerIO.screen(name: String.random) { result in
            guard case .failure(let error) = result else { return XCTFail() }
            guard case .http(let httpError) = error else { return XCTFail() }
            guard case .unsuccessfulStatusCode = httpError else { return XCTFail() }

            expect.fulfill()
        }
        customerIO.screen(name: String.random, data: ScreenViewData.random()) { result in
            guard case .failure(let error) = result else { return XCTFail() }
            guard case .http(let httpError) = error else { return XCTFail() }
            guard case .unsuccessfulStatusCode = httpError else { return XCTFail() }

            expect.fulfill()
        }

        waitForExpectations()
    }
    
    func test_screen_expectCallRepository() {
        let givenScreenName = String.random
        let givenData = ScreenViewData.random()

        identifyRepositoryMock.screenClosure = { actualScreenName, actualData, _, _, onComplete in
            XCTAssertEqual(givenScreenName, actualScreenName)
            XCTAssertEqual(givenData, actualData.value as! ScreenViewData)

            onComplete(Result.success(()))
        }

        let expect = expectation(description: "Expect to complete screen")
        customerIO.screen(name: givenScreenName, data: givenData) { result in
            expect.fulfill()
        }

        waitForExpectations()

        XCTAssertEqual(identifyRepositoryMock.screenCallsCount, 1)
    }
}
