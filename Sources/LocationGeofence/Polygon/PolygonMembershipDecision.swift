import Foundation

/// Decides what a fix establishes about a device's membership in a polygon.
///
/// The polygon counterpart of `BaselineHealDecision`, and deliberately the same guards applied to a
/// polygon's signed edge distance instead of a circle's: the fix must be recent, its accuracy
/// usable, and its distance from the boundary must exceed the ambiguity margin. This is the single
/// place a polygon verdict is formed, so "no event without gated geometric confirmation" is
/// enforced in one function rather than at each call site.
enum PolygonMembershipDecision {
    /// The membership the fix establishes, or `nil` when it cannot decide — a stale fix, an
    /// unusable accuracy, or a boundary inside the ambiguity band. Never returns `.unknown`:
    /// that is what the caller records in response to `nil`.
    ///
    /// - Parameter signedEdgeDistance: metres to the polygon boundary in `PolygonRegion`'s
    ///   convention — **positive inside**, which is the opposite of the circle path's edge
    ///   distance. Converting here rather than at call sites keeps the mismatch in one place.
    static func resolvedMembership(
        signedEdgeDistance: Double,
        horizontalAccuracy: Double,
        fixAge: TimeInterval
    ) -> PolygonMembership? {
        guard fixAge >= 0, fixAge <= GeofenceConstants.movementFixMaxAge else { return nil }
        guard horizontalAccuracy > 0 else { return nil }
        let margin = max(horizontalAccuracy, GeofenceConstants.baselineHealMinEdgeMargin)
        guard abs(signedEdgeDistance) > margin else { return nil }
        return signedEdgeDistance > 0 ? .inside : .outside
    }
}
