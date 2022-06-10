@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class CustomerIOIntegrationTest: IntegrationTest {
    override func setUp() {
        super.setUp()

        configureBackgroundQueue(minNumberOfTasks: 1) // run queue tasks immediately
    }

    func test_givenIdentifyProfileAttributesInAllCaps_expectSendToAPIInAllCaps() {
        let givenAttributes = ["CITY": "Chicago"]
        httpRequestRunnerStub.queueSuccessfulResponse()

        CustomerIO.shared.identify(identifier: String.random, body: givenAttributes)

        XCTAssertEqual(httpRequestRunnerStub.requestCallsCount, 1)
        XCTAssertEqual(httpRequestRunnerStub.lastRequestParams?.body?.string, #"{"CITY":"Chicago"}"#)
    }

    func test_givenProfileAttributesInAllCaps_expectSendToAPIInAllCaps() {
        let givenAttributes = ["CITY": "Chicago"]
        httpRequestRunnerStub.queueSuccessfulResponse()
        httpRequestRunnerStub.queueSuccessfulResponse()

        CustomerIO.shared.identify(identifier: String.random)
        CustomerIO.shared.profileAttributes = givenAttributes

        XCTAssertEqual(httpRequestRunnerStub.requestCallsCount, 2)
        XCTAssertEqual(httpRequestRunnerStub.lastRequestParams?.body?.string, #"{"CITY":"Chicago"}"#)
    }

    func test_givenTrackEventAttributesInAllCaps_expectSendToAPIInAllCaps() {
        let givenAttributes = ["CITY": "Chicago"]
        let givenEventName = String.random
        httpRequestRunnerStub.queueSuccessfulResponse()
        httpRequestRunnerStub.queueSuccessfulResponse()

        CustomerIO.shared.identify(identifier: String.random)
        CustomerIO.shared.track(name: givenEventName, data: givenAttributes)

        XCTAssertEqual(httpRequestRunnerStub.requestCallsCount, 2)
        XCTAssertEqual(httpRequestRunnerStub.lastRequestParams?.body?.string,
                       "{\"data\":{\"CITY\":\"Chicago\"},\"name\":\"\(givenEventName)\",\"timestamp\":\(dateUtilStub.givenNow.unixTime),\"type\":\"event\"}")
    }
}
