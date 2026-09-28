import CioInternalCommon
import Foundation

/// Decides whether a fresh fix contradicts a region's stored dedup baseline, i.e. whether a crossing
/// happened that the OS never delivered.
///
/// iOS can leave a device dwelling well inside an armed fence without ever generating the enter.
/// Every guard skips rather than risk a fabricated event: the fix must be
/// recent, and its distance from the fence EDGE must exceed its horizontal accuracy (floored by
/// `baselineHealMinEdgeMargin` against over-optimistic accuracy values).
enum BaselineHealDecision {
    /// The transition to synthesize, or `nil` to leave the baseline alone.
    static func synthesizedTransition(
        distanceFromCenter: Double,
        radius: Double,
        horizontalAccuracy: Double,
        fixAge: TimeInterval,
        lastState: GeofenceTransition?
    ) -> GeofenceTransition? {
        guard let lastState else { return nil }
        guard fixAge >= 0, fixAge <= GeofenceConstants.movementFixMaxAge else { return nil }
        guard horizontalAccuracy > 0 else { return nil }
        let edgeDistance = distanceFromCenter - radius
        let margin = max(horizontalAccuracy, GeofenceConstants.baselineHealMinEdgeMargin)
        guard abs(edgeDistance) > margin else { return nil }
        let actual: GeofenceTransition = edgeDistance < 0 ? .enter : .exit
        return actual == lastState ? nil : actual
    }
}
