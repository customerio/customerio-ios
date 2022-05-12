@testable import Common
import Foundation
import SharedTests
import XCTest

class QueueQueryRunnerTest: UnitTest {
    private var runner: QueueQueryRunner!

    override func setUp() {
        super.setUp()

        runner = CioQueueQueryRunner(logger: log)
    }

    // MARK: getNextTask

    func test_getNextTask_givenEmptyQueue_expectNil() {
        let queue: [QueueTaskMetadata] = []

        XCTAssertNil(runner.getNextTask(queue, lastFailedTask: nil))
    }

    func test_getNextTask_givenNoLastFailedTask_expectGetNextItemInQueue() {
        let queue = [
            QueueTaskMetadata.random,
            QueueTaskMetadata.random
        ]
        let expected = queue[0]

        let actual = runner.getNextTask(queue, lastFailedTask: nil)

        XCTAssertEqual(expected, actual)
    }

    func test_getNextTask_givenFailedTaskParentOfGroup_expectSkipGroupTasks() {
        let givenFailedTask = QueueTaskMetadata.random.groupStartSet(String.random)

        let queue = [
            QueueTaskMetadata.random.groupMemberSet([givenFailedTask.groupStart!]),
            QueueTaskMetadata.random
        ]
        let expected = queue[1]

        let actual = runner.getNextTask(queue, lastFailedTask: givenFailedTask)

        XCTAssertEqual(expected, actual)
    }

    func test_getNextTask_givenFailedTaskChildOfGroup_expectGetNextItemInQueue() {
        let givenFailedTask = QueueTaskMetadata.random.groupMemberSet([String.random])

        let queue = [
            QueueTaskMetadata.random.groupMemberSet(givenFailedTask.groupMember)
        ]
        let expected = queue[0]

        let actual = runner.getNextTask(queue, lastFailedTask: givenFailedTask)

        XCTAssertEqual(expected, actual)
    }
}
