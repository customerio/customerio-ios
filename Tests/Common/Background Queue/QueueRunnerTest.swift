@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class QueueRunnerTest: UnitTest {
    private var runner: CioQueueRunner!

    private let httpClientMock = HttpClientMock()

    override func setUp() {
        super.setUp()

        runner = CioQueueRunner(jsonAdapter: jsonAdapter, logger: log, httpClient: httpClientMock, hooksManager: diGraph.hooksManager, sdkConfig: sdkConfig)
    }

    // MARK: registerPushToken

    func test_registerPushToken_givenIdentifierEmpty_expectHttpRequestNotMade_expectBQDeletesTask() {
        let givenRegisterTokenTask = RegisterPushNotificationQueueTaskData(profileIdentifier: " ", attributesJsonString: nil)

        let givenQueueTask = QueueTask(storageId: .random, type: QueueTaskType.registerPushToken.rawValue, data: jsonAdapter.toJson(givenRegisterTokenTask)!, runResults: QueueTaskRunResults(totalRuns: 0))

        let expectToCompleteRunning = expectation(description: "expect to complete running")
        var actualResult: Result<Void, HttpRequestError>!
        runner.runTask(givenQueueTask) { result in
            actualResult = result
            expectToCompleteRunning.fulfill()
        }

        waitForExpectations()

        XCTAssertTrue(actualResult.isSuccess) // the BQ will delete the task if http was successful
        XCTAssertFalse(httpClientMock.mockCalled)
    }
}
