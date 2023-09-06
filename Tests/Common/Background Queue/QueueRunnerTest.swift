@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class QueueRunnerTest: UnitTest {
    private let httpClientMock = HttpClientMock()
    private let hooksMock = HooksManagerMock()

    private var queueRunner: QueueRunner!

    override func setUp() {
        super.setUp()

        queueRunner = CioQueueRunner(jsonAdapter: jsonAdapter, logger: log, httpClient: httpClientMock, hooksManager: hooksMock, sdkConfig: sdkConfig)
    }

    // MARK: runTask

    func test_runTask_givenTaskNotHandledByCommonModule_expectCheckHooksToRunTask() {
        let givenQueueTaskNotCreatedByCommonModule = QueueTask(storageId: .random, type: "not-a-common-task-type", data: "".data, runResults: QueueTaskRunResults(totalRuns: 0))
        let givenQueueRunnerThatRunsTask = getQueueRunner()

        hooksMock.underlyingQueueRunnerHooks = [givenQueueRunnerThatRunsTask]

        let expectToFinishRunning = expectation(description: "Expect to finish running")
        queueRunner.runTask(givenQueueTaskNotCreatedByCommonModule) { _ in
            expectToFinishRunning.fulfill()
        }

        waitForExpectations()

        XCTAssertEqual(hooksMock.queueRunnerHooksGetCallsCount, 1)
        XCTAssertEqual(givenQueueRunnerThatRunsTask.runTaskCallsCount, 1)
    }
}

private extension QueueRunnerTest {
    func getQueueRunner() -> QueueRunnerHookMock {
        let queueRunner = QueueRunnerHookMock()
        queueRunner.runTaskClosure = { _, onComplete in
            onComplete(.success(()))

            return true // to indicate that the hook handled the run request
        }
        return queueRunner
    }
}
