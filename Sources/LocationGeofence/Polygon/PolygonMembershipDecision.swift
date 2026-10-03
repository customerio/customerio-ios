import Foundation

/// No margin floor, unlike `BaselineHealDecision`: a floor would refuse most of a shallow venue. The
/// margin is the fix's own accuracy, capped per fence by `venueScale`.
enum PolygonMembershipDecision {
    enum Outcome: Equatable {
        case decided(PolygonMembership)
        /// Inside by less than the fix's accuracy. Only ever `.inside`.
        case needsCorroboration(PolygonMembership)
        case undecided(PolygonUndecidedReason)
    }

    /// Test-only; the resolver uses `resolvedOutcome`.
    static func resolvedMembership(
        signedEdgeDistance: Double,
        horizontalAccuracy: Double,
        fixAge: TimeInterval
    ) -> PolygonMembership? {
        switch resolvedOutcome(
            signedEdgeDistance: signedEdgeDistance,
            horizontalAccuracy: horizontalAccuracy,
            fixAge: fixAge,
            venueScale: .infinity
        ) {
        case .decided(let membership): return membership
        case .needsCorroboration, .undecided: return nil
        }
    }

    /// Asymmetric on purpose: a refused arrival is lost (a stationary device gets no later pass),
    /// while a spurious one is corrected by the next decisive fix.
    static func resolvedOutcome(
        signedEdgeDistance: Double,
        horizontalAccuracy: Double,
        fixAge: TimeInterval,
        venueScale: Double
    ) -> Outcome {
        guard fixAge >= 0, fixAge <= GeofenceConstants.movementFixMaxAge else {
            return .undecided(.fixTooOld)
        }
        guard horizontalAccuracy > 0 else { return .undecided(.noUsableFix) }
        // Before the ceiling: clear of the ring by more than the accuracy is outside, however thin
        // the venue.
        if signedEdgeDistance < 0, -signedEdgeDistance > horizontalAccuracy {
            return .decided(.outside)
        }
        guard horizontalAccuracy < venueScale else { return .undecided(.accuracyTooLow) }
        if signedEdgeDistance > horizontalAccuracy { return .decided(.inside) }
        return signedEdgeDistance > 0 ? .needsCorroboration(.inside) : .undecided(.withinAccuracy)
    }
}
