import CioInternalCommon
import Foundation

/// Whether a fresh fix contradicts a region's stored baseline (a crossing the OS never delivered).
/// Every guard skips rather than risk a fabricated event.
enum BaselineHealDecision {
    static func synthesizedTransition(
        distanceFromCenter: Double,
        radius: Double,
        horizontalAccuracy: Double,
        fixAge: TimeInterval,
        lastState: GeofenceTransition?
    ) -> GeofenceTransition? {
        guard let lastState,
              let actual = settledSide(
                  distanceFromCenter: distanceFromCenter, radius: radius,
                  horizontalAccuracy: horizontalAccuracy, fixAge: fixAge
              )
        else { return nil }
        return actual == lastState ? nil : actual
    }

    /// The side of the fence a fix settles — `.enter` inside, `.exit` outside — or `nil` when the
    /// guards above leave it undecided.
    static func settledSide(
        distanceFromCenter: Double,
        radius: Double,
        horizontalAccuracy: Double,
        fixAge: TimeInterval
    ) -> GeofenceTransition? {
        guard fixAge >= 0, fixAge <= GeofenceConstants.movementFixMaxAge else { return nil }
        guard horizontalAccuracy > 0 else { return nil }
        let edgeDistance = distanceFromCenter - radius
        let margin = max(horizontalAccuracy, GeofenceConstants.baselineHealMinEdgeMargin)
        guard abs(edgeDistance) > margin else { return nil }
        return edgeDistance < 0 ? .enter : .exit
    }
}
