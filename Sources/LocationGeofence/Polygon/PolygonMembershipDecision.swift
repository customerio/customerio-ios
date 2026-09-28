import Foundation

/// Decides what a fix establishes about a device's membership in a polygon. The single place a
/// polygon verdict is formed: the fix must be recent, its accuracy usable, and its distance from
/// the boundary must exceed that accuracy.
///
/// No margin floor, unlike `BaselineHealDecision`'s `baselineHealMinEdgeMargin`: a floor refuses
/// every fix within that distance of an edge, which is most of a shallow venue. The margin is the
/// fix's own accuracy, capped per fence by `venueScale`.
enum PolygonMembershipDecision {
    /// What a single fix establishes. Three states, not two: a fix can be good enough to trust
    /// while still being too close to the boundary to trust ALONE.
    enum Outcome: Equatable {
        /// The fix separates inside from outside on its own.
        case decided(PolygonMembership)
        /// The fix says inside, but `|edge|` is inside its own accuracy. A second agreeing fix
        /// settles it. Only ever `.inside`: see `resolvedOutcome`.
        case needsCorroboration(PolygonMembership)
        case undecided(PolygonUndecidedReason)
    }

    /// The membership a single fix establishes, or `nil` when it cannot decide alone.
    ///
    /// No production caller: the resolver uses `resolvedOutcome`. Only tests call it.
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

    /// The full arrival rule, asymmetric on purpose. Refusing a real arrival is the expensive
    /// error: a stationary device gets no later pass to re-derive it, so the visit is lost. A
    /// spurious arrival at the boundary is corrected by the next decisive fix. So an ambiguous
    /// INSIDE is worth a second fix, and an ambiguous outside is no verdict.
    ///
    /// A fix-derived departure therefore needs clearance beyond the accuracy, so an ambiguous fix
    /// can never end a visit early. The covering-circle exit does not go through this rule.
    ///
    /// - Parameter venueScale: `PolygonRegion.scale`, roughly how deep the venue is. Once the
    ///   accuracy is that wide the accuracy circle can contain the whole ring and "inside" carries
    ///   no information. Per fence because venue depths differ by an order of magnitude. Caps
    ///   ARRIVALS only; the decisive-outside check runs first.
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
        // Must run before the ceiling: a device clear of the ring by more than its accuracy is
        // outside however thin the venue is. Behind the ceiling, a shallow ring would refuse every
        // departure a coarse fix can prove, leaving the visit open inside a covering circle that no
        // circle exit will close, so the next return misses its enter.
        if signedEdgeDistance < 0, -signedEdgeDistance > horizontalAccuracy {
            return .decided(.outside)
        }
        guard horizontalAccuracy < venueScale else { return .undecided(.accuracyTooLow) }
        if signedEdgeDistance > horizontalAccuracy { return .decided(.inside) }
        // Ambiguous. Inside is worth a second look, but only so a fix that positively reads
        // OUTSIDE can block it — an unanswered second opinion still commits. Outside is not a
        // verdict either way.
        return signedEdgeDistance > 0 ? .needsCorroboration(.inside) : .undecided(.withinAccuracy)
    }
}
