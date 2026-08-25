import CioInternalCommon
import Foundation

/// Decides whether a sync pass should synthesize a crossing for an already-registered region whose
/// stored dedup baseline contradicts the pass's fix.
///
/// iOS region monitoring is conservative about promoting crossings from coarse passive fixes — a
/// device can dwell well inside an armed fence without the OS ever generating the enter (observed
/// on device, 2026-08-08). The sync pass carries a fresh, actively-requested fix; when that fix
/// places the device unambiguously on the other side of the fence from the stored baseline, the
/// crossing genuinely happened and the OS missed it — deliver it ourselves.
///
/// Guards, all of which SKIP the heal (today's behavior) rather than risk a fabricated event:
/// - the fix must be recent (a stale fix says where the device was, not where it is), and
/// - the fix's distance from the fence EDGE must exceed its horizontal accuracy (with a floor
///   against over-optimistic accuracy values) — inside the ambiguity band, no verdict.
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
