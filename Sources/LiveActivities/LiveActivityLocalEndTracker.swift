import CioInternalCommon
import Foundation

/// Tracks activities the SDK ended locally (via `CIOLiveActivity.end`) so observation can tell a
/// user's manual dismissal apart from an app/SDK-initiated end.
///
/// When the host app ends an activity through the handle, the local-end path already reports the
/// `end` event, so the marker lets observation *suppress* the terminal-state signal instead of
/// double-reporting. Anything that reaches `.dismissed` without a marker (and without first passing
/// through `.ended`) is a genuine user swipe-away, which observation then reports — mirroring
/// Android, where a notification's delete-intent fires only on user dismissal, never on a
/// programmatic cancel.
final class LiveActivityLocalEndTracker: @unchecked Sendable {
    private let ids = Synchronized<Set<String>>([])

    /// Mark that `activityInstanceId` is being ended locally by the SDK.
    func markEnded(_ activityInstanceId: String) {
        ids.mutating { $0.insert(activityInstanceId) }
    }

    /// Returns whether `activityInstanceId` was marked as a local end, clearing the marker so it
    /// is consumed exactly once.
    func consume(_ activityInstanceId: String) -> Bool {
        ids.mutating { set in
            guard set.contains(activityInstanceId) else { return false }
            set.remove(activityInstanceId)
            return true
        }
    }

    /// Drop all markers (used on reset).
    func clearAll() {
        ids.wrappedValue = []
    }
}
