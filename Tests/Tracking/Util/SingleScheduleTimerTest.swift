@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class SingleScheduleTimerTest: UnitTest {
    private var timer: SingleScheduleTimer!

    override func setUp() {
        super.setUp()

        timer = CioSingleScheduleTimer()
    }

    // MARK: scheduleIfNotAleady

    func test_scheduleIfNotAleady_givenCallMultipleTimes_expectIgnoreFutureRequests() {
        let expectation = expectation(description: "Timer fires")
        var didSchedule = timer.scheduleIfNotAleady(numSeconds: 0.1) {
            expectation.fulfill()
        }
        XCTAssertTrue(didSchedule)

        didSchedule = timer.scheduleIfNotAleady(numSeconds: 0) {
            expectation.fulfill() // this should not fire
        }
        XCTAssertFalse(didSchedule)

        waitForExpectations()
    }

    func test_scheduleIfNotAleady_givenCallAfterTimerFires_expectStartNewTimer() {
        var expect = expectation(description: "Timer fires")
        var didSchedule = timer.scheduleIfNotAleady(numSeconds: 0) {
            expect.fulfill()
        }
        XCTAssertTrue(didSchedule)
        waitForExpectations()

        expect = expectation(description: "Timer fires")
        didSchedule = timer.scheduleIfNotAleady(numSeconds: 0) {
            expect.fulfill()
        }
        XCTAssertTrue(didSchedule)
        waitForExpectations()
    }

    // MARK: cancel

    func test_cancel_givenNoScheduleScheduled_expectNoErrors() {}

    func test_cancel_givenScheduled_expectTimerCanceled() {}

    func test_cancel_expectScheduleAfterCancel() {}
}
