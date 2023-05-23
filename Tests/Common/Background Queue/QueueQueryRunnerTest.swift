@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class QueueQueryRunnerTest: UnitTest {
    private var runner: CioQueueQueryRunner!

    override func setUp() {
        super.setUp()

        runner = CioQueueQueryRunner(logger: log)
    }

    // MARK: getNextTask

    func test_getNextTask_givenEmptyQueue_expectNil() {
        let queue: [QueueTaskMetadata] = []

        XCTAssertNil(runner.getNextTask(queue, lastRanTask: nil, lastFailedTask: nil))
    }

    func test_getNextTask_givenNoLastFailedTask_expectGetNextItemInQueue() {
        let queue = [
            QueueTaskMetadata.random,
            QueueTaskMetadata.random
        ]
        let expected = queue[0]

        let actual = runner.getNextTask(queue, lastRanTask: nil, lastFailedTask: nil)

        XCTAssertEqual(expected, actual)
    }

    func test_getNextTask_givenLastRanTask_expectGetNextItemInQueueAfterLastRanTask() {
        let queue = [
            QueueTaskMetadata.random,
            QueueTaskMetadata.random
        ]
        let expected = queue[1]

        let actual = runner.getNextTask(queue, lastRanTask: queue[0], lastFailedTask: nil)

        XCTAssertEqual(expected, actual)
    }

    func test_getNextTask_givenFailedTaskParentOfGroup_expectSkipGroupTasks() {
        let givenFailedTask = QueueTaskMetadata.random.groupStartSet(String.random)

        let queue = [
            QueueTaskMetadata.random.groupMemberSet([givenFailedTask.groupStart!]),
            QueueTaskMetadata.random
        ]
        let expected = queue[1]

        let actual = runner.getNextTask(queue, lastRanTask: nil, lastFailedTask: givenFailedTask)

        XCTAssertEqual(expected, actual)
    }

    func test_getNextTask_givenFailedTaskChildOfGroup_expectGetNextItemInQueue() {
        let givenFailedTask = QueueTaskMetadata.random.groupMemberSet([String.random])

        let queue = [
            QueueTaskMetadata.random.groupMemberSet(givenFailedTask.groupMember)
        ]
        let expected = queue[0]

        let actual = runner.getNextTask(queue, lastRanTask: nil, lastFailedTask: givenFailedTask)

        XCTAssertEqual(expected, actual)
    }

    // reset

    func test_reset_givenCriteriaEmpty_expectCriteriaToRemainEmpty() {
        assertQueryCriteriaEmpty(isEmpty: true)

        runner.reset()

        assertQueryCriteriaEmpty(isEmpty: true)
    }

    func test_reset_givenCriteriaNotEmpty_expectCriteriaToBecomeEmpty() {
        runner.updateCriteria(lastFailedTask: QueueTaskMetadata.random.groupStartSet(String.random))
        assertQueryCriteriaEmpty(isEmpty: false)

        runner.reset()

        assertQueryCriteriaEmpty(isEmpty: true)
    }

    private func assertQueryCriteriaEmpty(isEmpty: Bool) {
        if isEmpty {
            XCTAssertTrue(runner.queryCriteria.excludeGroups.isEmpty)
        } else {
            XCTAssertFalse(runner.queryCriteria.excludeGroups.isEmpty)
        }
    }
}
