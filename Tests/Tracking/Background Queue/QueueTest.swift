@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class QueueTest: UnitTest {
    var queue: Queue!

    override func setUp() {
        super.setUp()

        queue = DITracking(siteId: String.random).queue
    }

    func test_addTaskTwice_expectQueueHave2Items() {
        let givenType = QueueTaskType.identifyProfile
        let givenTaskData = ["push_id": 5]

        let actual1 = queue.addTask(type: givenType, data: jsonAdapter.toJson(givenTaskData, encoder: nil)!)

        XCTAssertTrue(actual1.success)
        XCTAssertEqual(actual1.queueStatus.numTasksInQueue, 1)

        let actual2 = queue.addTask(type: givenType, data: jsonAdapter.toJson(givenTaskData, encoder: nil)!)

        XCTAssertTrue(actual2.success)
        XCTAssertEqual(actual2.queueStatus.numTasksInQueue, 2)
    }
}
