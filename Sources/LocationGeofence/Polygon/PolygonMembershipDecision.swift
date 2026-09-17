import Foundation

/// Decides what a fix establishes about a device's membership in a polygon.
///
/// The polygon counterpart of `BaselineHealDecision`: the fix must be recent, its accuracy usable,
/// and its distance from the boundary must exceed the ambiguity margin. This is the single place a
/// polygon verdict is formed, so "no event without gated geometric confirmation" is enforced in one
/// function rather than at each call site.
///
/// Unlike heal, there is no margin FLOOR. Heal borrowed one (`baselineHealMinEdgeMargin`, 20 m)
/// and this used to as well, which made a retail venue undecidable rather than safe: on the
/// measured Tim Hortons ring, whose deepest point is 24 m, a 20 m floor left 3% of the interior
/// claimable. The margin here is the fix's own accuracy, bounded per fence by `venueScale`.
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
    /// No production caller: `resolvedOutcome` is the rule the resolver uses. Kept because the
    /// cross-SDK sign-convention fixtures assert against it, and a single-fix answer is the form
    /// those fixtures are written in on both platforms.
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

    /// The full arrival rule.
    ///
    /// Asymmetric on purpose, and the asymmetry is the point: refusing a real arrival is the
    /// expensive error, because while the device is stationary nothing re-derives it — no movement
    /// pass runs, so the visit is lost rather than late. A spurious arrival at the boundary is
    /// cheap by comparison: the person is standing at the venue, and the next decisive fix
    /// corrects the belief. So an ambiguous fix that says INSIDE is worth a second look, while an
    /// ambiguous fix that says outside is simply not a verdict.
    ///
    /// That also makes a FIX-DERIVED departure strict for free, with no reference to the stored
    /// belief: it needs `.decided(.outside)`, which requires clearance beyond the accuracy, so an
    /// ambiguous fix can never end a visit early. It says nothing about the covering-circle exit
    /// path, which applies `.outside` with `confirmedByFix: false` and consults no fix at all —
    /// deliberately, since polygon ⊆ circle makes leaving the circle a verdict no ring can
    /// contradict.
    ///
    /// - Parameter venueScale: `PolygonRegion.scale` — roughly how deep the venue is. Once the
    ///   accuracy circle is that wide it can contain the whole ring, so "inside" stops carrying
    ///   information and no number of agreeing fixes fixes that. This is the ceiling, and it is
    ///   per-fence rather than a global constant precisely because the venues differ by an order
    ///   of magnitude (24 m to 229 m across the four rings measured 2026-09-16). Gates ARRIVALS
    ///   only — see the decisive-outside branch, which runs ahead of it.
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
        // Ahead of the ceiling, and it must be. The ceiling asks whether the venue is deep enough
        // to be confidently INSIDE; a device clear of the ring by more than its own accuracy is
        // outside no matter how thin the venue is, and that argument does not weaken as the venue
        // narrows — it strengthens. Behind the ceiling, a 20 m-deep ring refused every departure
        // a coarse fix could prove, leaving the visit open inside the far larger covering circle
        // where no circle exit will close it either, so the next return misses its enter.
        if signedEdgeDistance < 0, -signedEdgeDistance > horizontalAccuracy {
            return .decided(.outside)
        }
        guard horizontalAccuracy < venueScale else { return .undecided(.accuracyTooLow) }
        if signedEdgeDistance > horizontalAccuracy { return .decided(.inside) }
        // Ambiguous. Inside is worth corroborating; outside is not a verdict.
        return signedEdgeDistance > 0 ? .needsCorroboration(.inside) : .undecided(.withinAccuracy)
    }
}
