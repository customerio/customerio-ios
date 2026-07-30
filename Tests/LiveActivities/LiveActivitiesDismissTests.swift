import Foundation
import Testing

@testable import CioLiveActivities

// MARK: - Terminal-state discriminator (user dismiss vs app/backend end)

struct LiveActivityTerminalActionTests {
    @Test func dismissedFirst_notLocalEnd_isUserDismiss() {
        // User swiped it away: first terminal state is `.dismissed`, SDK didn't end it.
        #expect(liveActivityTerminalAction(firstTerminalIsDismissed: true, wasLocalEnd: false) == .reportUserDismiss)
    }

    @Test func endedFirst_isCleanupOnly() {
        // App/SDK/backend/system end: first terminal state is `.ended` — never a user dismiss.
        #expect(liveActivityTerminalAction(firstTerminalIsDismissed: false, wasLocalEnd: false) == .cleanupOnly)
    }

    @Test func dismissedFirst_butLocalEnd_isCleanupOnly() {
        // Local `end(.immediate)` whose `.ended` the stream coalesced to `.dismissed`: the marker
        // suppresses a spurious user-dismiss report (the handle already reported the end).
        #expect(liveActivityTerminalAction(firstTerminalIsDismissed: true, wasLocalEnd: true) == .cleanupOnly)
    }

    @Test func endedFirst_localEnd_isCleanupOnly() {
        #expect(liveActivityTerminalAction(firstTerminalIsDismissed: false, wasLocalEnd: true) == .cleanupOnly)
    }
}

// MARK: - Local-end tracker

struct LiveActivityLocalEndTrackerTests {
    @Test func consume_returnsFalse_whenNotMarked() {
        let tracker = LiveActivityLocalEndTracker()
        #expect(tracker.consume("i1") == false)
    }

    @Test func consume_returnsTrueOnce_afterMark() {
        let tracker = LiveActivityLocalEndTracker()
        tracker.markEnded("i1")
        #expect(tracker.consume("i1") == true)
        // Consumed exactly once — a later terminal state for the same id reads false.
        #expect(tracker.consume("i1") == false)
    }

    @Test func markAndConsume_areKeyedPerActivity() {
        let tracker = LiveActivityLocalEndTracker()
        tracker.markEnded("i1")
        #expect(tracker.consume("i2") == false)
        #expect(tracker.consume("i1") == true)
    }

    @Test func clearAll_dropsMarkers() {
        let tracker = LiveActivityLocalEndTracker()
        tracker.markEnded("i1")
        tracker.markEnded("i2")
        tracker.clearAll()
        #expect(tracker.consume("i1") == false)
        #expect(tracker.consume("i2") == false)
    }
}
