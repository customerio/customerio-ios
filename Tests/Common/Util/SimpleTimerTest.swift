@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class SimpleTimerTest: UnitTest {
    private var timer: CioSimpleTimer!

    override func setUp() {
        super.setUp()

        timer = CioSimpleTimer(logger: log)
    }

    // MARK: scheduleIfNotAlready

    func test_scheduleIfNotAlready_givenCallMultipleTimes_expectIgnoreFutureRequests() {
        let expect = expectation(description: "Timer fires")
        var didSchedule = timer.scheduleIfNotAlready(seconds: 0.1) {
            expect.fulfill()
        }
        XCTAssertTrue(didSchedule)

        didSchedule = timer.scheduleIfNotAlready(seconds: 0) {
            expect.fulfill() // this should not fire
        }
        XCTAssertFalse(didSchedule)

        waitForExpectations()
    }

    func test_scheduleIfNotAlready_givenCallAfterTimerFires_expectStartNewTimer() {
        var expect = expectation(description: "Timer fires")
        var didSchedule = timer.scheduleIfNotAlready(seconds: 0) {
            expect.fulfill()
        }
        XCTAssertTrue(didSchedule)
        waitForExpectations()

        expect = expectation(description: "Timer fires")
        didSchedule = timer.scheduleIfNotAlready(seconds: 0) {
            expect.fulfill()
        }
        XCTAssertTrue(didSchedule)
        waitForExpectations()
    }

    // MARK: scheduleAndCancelPrevious

    func test_schedule_givenPreviouslyRunningTimer_expectCancelAndStartNew() {
        let expectNoFire = expectation(description: "Timer does not fire")
        expectNoFire.isInverted = true
        timer.scheduleAndCancelPrevious(seconds: 1) {
            expectNoFire.fulfill()
        }

        timer.cancel()

        let expectFire = expectation(description: "Timer fires")
        timer.scheduleAndCancelPrevious(seconds: 0.1) {
            expectFire.fulfill()
        }

        waitForExpectations()
    }

    // MARK: cancel

    func test_cancel_givenNoScheduleScheduled_expectNoErrors() {
        timer.cancel()
    }

    func test_cancel_givenScheduled_expectTimerCanceled() {
        let expect = expectation(description: "Timer does not fire")
        expect.isInverted = true
        let didSchedule = timer.scheduleIfNotAlready(seconds: 0.1) {
            expect.fulfill()
        }
        XCTAssertTrue(didSchedule)

        timer.cancel()

        waitForExpectations()
    }

    func test_cancel_expectScheduleAfterCancel() {
        let expectNoFire = expectation(description: "Timer does not fire")
        expectNoFire.isInverted = true
        var didSchedule = timer.scheduleIfNotAlready(seconds: 0.1) {
            expectNoFire.fulfill()
        }
        XCTAssertTrue(didSchedule)

        timer.cancel()

        let expectFire = expectation(description: "Timer fires")
        didSchedule = timer.scheduleIfNotAlready(seconds: 0.1) {
            expectFire.fulfill()
        }
        XCTAssertTrue(didSchedule)

        waitForExpectations()
    }
}
