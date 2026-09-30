import CioInternalCommon
import Foundation

/// Carries the fix: an OS event isn't a live anchor, so without it the coordinator widens the wake
/// trigger to the full refresh radius.
enum PolygonTransitionOutcome: Equatable {
    case circleEntered(fix: ResolvedFix)
    case nothingToRearm
}
