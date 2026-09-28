import CioInternalCommon
import Foundation

/// What a delivered business-geofence transition leaves for the caller to do about the wake.
///
/// The OS watches only a polygon's covering circle, so after a circle entry the only wake for the
/// polygon crossing is the movement trigger. That trigger is sized at registration, and the OS
/// event does not re-arm it, so without a re-arm the device keeps whatever trigger it arrived
/// with (after a drive, the full refresh radius).
///
/// Carries the fix because the wake cannot be sized without one: OS-delivered business events
/// have `locationIsFresh == false`, and `GeofenceSyncCoordinator` widens the trigger to the full
/// refresh radius for any non-live anchor. Handing the fix on also stops the follow-up pass
/// requesting the same moment again. It is the fix the membership pass already obtained and
/// gated, so it costs no extra request.
enum PolygonTransitionOutcome: Equatable {
    /// A polygon's covering circle was entered and this fix decided the membership question.
    case circleEntered(fix: ResolvedFix)
    /// Everything else: a circle fence, an uncached id, any exit, or an enter that produced no
    /// usable fix. Nothing here changes what the wake should be sized against.
    case nothingToRearm
}
