@testable import CioTracking
@testable import Common
import Foundation
import SharedTests
import XCTest

class TrackingIntegrationTest: IntegrationTest {
    private var queue: Queue {
        diGraph.queue
    }

    // Common set of custom attributes that tries to demonstrate all of the different ways the customers might use
    // attributes to verify we support it all.
    let givenCustomAttributes: [String: Any] = [
        "firstName": "Dana",
        "last_name": "Green",
        "HOBBY": "football",
        "nested": [
            "is adult": true,
            "age": 20
        ]
    ]
    let expectedCustomAttributesString = """
    "firstName":"Dana","HOBBY":"football","last_name":"Green","nested":{"age":20,"is adult":true}
    """.trimmingCharacters(in: .whitespacesAndNewlines)

    func test_identify_givenCustomAttributes_expectDoNotModifyCustomAttributes() {
        httpRequestRunnerStub.queueSuccessfulResponse()

        CustomerIO.shared.identify(identifier: .random, body: givenCustomAttributes)

        waitForQueueToFinishRunningTasks()

        XCTAssertEqual(httpRequestRunnerStub.requestCallsCount, 1)

        let requestParams = httpRequestRunnerStub.requestsParams[0]
        let actualRequestBodyString = requestParams.body!.string!
        let expectedRequestBodyString = """
        {\(expectedCustomAttributesString)}
        """.trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertEqual(expectedRequestBodyString, actualRequestBodyString)
    }

    func test_trackEvent_givenCustomAttributes_expectDoNotModifyCustomAttributes() {
        httpRequestRunnerStub.queueSuccessfulResponse() // for identify
        httpRequestRunnerStub.queueSuccessfulResponse() // for track

        CustomerIO.shared.identify(identifier: .random) // can't track until you identify
        CustomerIO.shared.track(name: "foo", data: givenCustomAttributes)

        waitForQueueToFinishRunningTasks()

        XCTAssertEqual(httpRequestRunnerStub.requestCallsCount, 2)

        let requestParams = httpRequestRunnerStub.requestsParams[1]
        let actualRequestBodyString = requestParams.body!.string!
        let expectedRequestBodyString = """
        {"data":{\(expectedCustomAttributesString)},"name":"foo","timestamp":\(givenTimestampNow),"type":"event"}
        """.trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertEqual(expectedRequestBodyString, actualRequestBodyString)
    }

    func test_screenEvent_givenCustomAttributes_expectDoNotModifyCustomAttributes() {
        httpRequestRunnerStub.queueSuccessfulResponse() // for identify
        httpRequestRunnerStub.queueSuccessfulResponse() // for track

        CustomerIO.shared.identify(identifier: .random) // can't track until you identify
        CustomerIO.shared.screen(name: "foo", data: givenCustomAttributes)

        waitForQueueToFinishRunningTasks()

        XCTAssertEqual(httpRequestRunnerStub.requestCallsCount, 2)

        let requestParams = httpRequestRunnerStub.requestsParams[1]
        let actualRequestBodyString = requestParams.body!.string!
        let expectedRequestBodyString = """
        {"data":{\(expectedCustomAttributesString)},"name":"foo","timestamp":\(givenTimestampNow),"type":"screen"}
        """.trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertEqual(expectedRequestBodyString, actualRequestBodyString)
    }

    func test_registerDeviceToken_givenCustomAttributes_expectDoNotModifyCustomAttributes() {
        httpRequestRunnerStub.queueSuccessfulResponse() // for identify
        httpRequestRunnerStub.queueSuccessfulResponse() // for register token
        httpRequestRunnerStub.queueSuccessfulResponse() // for 2nd call to register token with custom attributes
        let givenDeviceToken = String.random

        CustomerIO.shared.identify(identifier: .random) // can't track until you identify
        CustomerIO.shared.registerDeviceToken(givenDeviceToken)
        CustomerIO.shared.deviceAttributes = givenCustomAttributes

        waitForQueueToFinishRunningTasks()

        XCTAssertEqual(httpRequestRunnerStub.requestCallsCount, 3)

        let requestParams = httpRequestRunnerStub.requestsParams[2]
        let actualRequestBodyString = requestParams.body!.string!
        let expectedRequestBodyString = """
        {"device":{"attributes":{"app_version":"1.30.887","cio_sdk_version":"2.0.3","device_locale":"en-US","device_manufacturer":"Apple","device_model":"iPhone 14","device_os":"14","firstName":"Dana","HOBBY":"football","last_name":"Green","nested":{"age":20,"is adult":true},"push_enabled":"false"},"id":"\(
            givenDeviceToken
        )","last_used":1670443977,"platform":"iOS"}}
        """.trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertEqual(expectedRequestBodyString, actualRequestBodyString)
    }
}

extension TrackingIntegrationTest {
    func waitForQueueToFinishRunningTasks(
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let queueExpectation = expectation(description: "Expect queue to run all tasks.")
        queue.run {
            queueExpectation.fulfill()
        }

        waitForExpectations(for: [queueExpectation], file: file, line: line)
    }
}
