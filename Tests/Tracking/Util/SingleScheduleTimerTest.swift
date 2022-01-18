@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class SingleScheduleTimerTest: UnitTest {
    private var timer: SingleScheduleTimer!

    override func setUp() {
        super.setUp()

        timer = CioSingleScheduleTimer(lockManager: lockManager)
    }

    // MARK: scheduleIfNotAleady

    func test_scheduleIfNotAleady_givenCallMultipleTimes_expectIgnoreFutureRequests() {
        let expect = expectation(description: "Timer fires")
        var didSchedule = timer.scheduleIfNotAleady(numSeconds: 0.1) {
            expect.fulfill()
        }
        XCTAssertTrue(didSchedule)

        didSchedule = timer.scheduleIfNotAleady(numSeconds: 0) {
            expect.fulfill() // this should not fire
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

    func test_cancel_givenNoScheduleScheduled_expectNoErrors() {
        timer.cancel()
    }

    func test_cancel_givenScheduled_expectTimerCanceled() {
        let expect = expectation(description: "Timer does not fire")
        expect.isInverted = true
        let didSchedule = timer.scheduleIfNotAleady(numSeconds: 0.1) {
            expect.fulfill()
        }
        XCTAssertTrue(didSchedule)

        timer.cancel()

        waitForExpectations()
    }

    func test_cancel_expectScheduleAfterCancel() {
        let expectNoFire = expectation(description: "Timer does not fire")
        expectNoFire.isInverted = true
        var didSchedule = timer.scheduleIfNotAleady(numSeconds: 0.1) {
            expectNoFire.fulfill()
        }
        XCTAssertTrue(didSchedule)

        timer.cancel()

        let expectFire = expectation(description: "Timer fires")
        didSchedule = timer.scheduleIfNotAleady(numSeconds: 0.1) {
            expectFire.fulfill()
        }
        XCTAssertTrue(didSchedule)

        waitForExpectations()
    }
}
