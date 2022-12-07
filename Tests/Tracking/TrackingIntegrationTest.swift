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
    "firstName":"Dana","HOBBY":"football","last_name":"Green","nested":{"age":20,"is adult":true}}
    """.trimmingCharacters(in: .whitespacesAndNewlines)

    func test_givenX_expectY() {
        httpRequestRunnerStub.queueSuccessfulResponse() // for identify
        httpRequestRunnerStub.queueSuccessfulResponse() // for track

        CustomerIO.shared.identify(identifier: .random) // can't track until you identify
        CustomerIO.shared.track(name: "foo", data: givenCustomAttributes)

        waitForQueueToFinishRunningTasks()

        XCTAssertEqual(httpRequestRunnerStub.requestCallsCount, 2)

        let trackEventRequestParams = httpRequestRunnerStub.requestsParams[1]
        let actualRequestBodyString = trackEventRequestParams.body!.string!
        let expectedRequestBodyString = """
        {"data":{\(expectedCustomAttributesString)},"name":"foo","timestamp":\(givenTimestampNow),"type":"event"}
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
