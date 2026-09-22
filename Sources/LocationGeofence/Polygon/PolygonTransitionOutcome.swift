import CioInternalCommon
import Foundation

/// What a delivered business-geofence transition leaves for the caller to do about the wake.
///
/// The OS monitors a polygon's covering circle and knows nothing about the polygon inside it, so
/// entering that circle puts the device next to a boundary no OS event can report. The only thing
/// that can wake us for the crossing is the movement trigger, and it is sized at registration
/// time — a circle entry does not re-arm it. A device that enters the circle and then walks to the
/// polygon carries whatever trigger it arrived with, which after a drive is the full refresh
/// radius, and nothing wakes us until it moves that far again.
///
/// Carries the fix rather than a bare flag because the wake radius cannot be sized without one.
/// The transition itself dispatches with `locationIsFresh == false` on both monitor paths —
/// business events deliberately carry their coordinates "for context only" — and
/// `GeofenceSyncCoordinator` widens the trigger to the full refresh radius for any anchor that is
/// not a live fix. Re-arming on the callback's own coordinates would therefore install the widest
/// possible trigger in exactly the case that needs the tightest. The fix here is the one the
/// membership pass already obtained and gated, so it costs no extra request.
enum PolygonTransitionOutcome: Equatable {
    /// A polygon's covering circle was entered and this fix decided the membership question.
    case circleEntered(fix: LocationData)
    /// Everything else: a circle fence, an uncached id, any exit, or an enter that produced no
    /// usable fix. Nothing here changes what the wake should be sized against.
    case nothingToRearm
}
