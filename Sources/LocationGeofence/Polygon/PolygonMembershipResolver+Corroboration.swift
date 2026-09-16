import CioInternalCommon
import CoreLocation
import Foundation

/// What a corroboration attempt yielded. Three cases, not an optional: a capture has to tell an
/// echo of the first fix apart from no fix at all, and that is the difference between "the rule
/// refused" and "location was unavailable".
enum CorroborationOutcome: Equatable {
    case obtained(CLLocation)
    /// A fix came back, but not newer than the one being corroborated — the first fix over again.
    case notIndependent
    case unavailable

    /// The fix when there was one, for callers that do not branch on the refusal.
    var fix: CLLocation? {
        if case .obtained(let fix) = self { return fix }
        return nil
    }
}

/// The second-fix confirmation for a marginal arrival, split from the resolver's core so both stay
/// under the file cap. `corroborate` is `internal` rather than `private` only because of this
/// split; it remains implementation detail of the resolver.
extension PolygonMembershipResolver {
    /// Applies the arrival rule to one fix, corroborating a marginal inside when needed.
    ///
    /// - Returns: the membership and whether it took a second fix, or `nil` after logging why no
    ///   verdict was reached.
    func settleMembership(
        fix: CLLocation,
        geofence: Geofence,
        polygon: PolygonRegion,
        signedEdgeDistance: Double
    ) async -> (PolygonMembership, Bool)? {
        switch PolygonMembershipDecision.resolvedOutcome(
            signedEdgeDistance: signedEdgeDistance,
            horizontalAccuracy: fix.horizontalAccuracy,
            fixAge: -fix.timestamp.timeIntervalSinceNow,
            venueScale: polygon.scale
        ) {
        case .decided(let decided):
            return (decided, false)
        case .undecided(let reason):
            logger.geofencePolygonUndecided(
                identifier: geofence.id, reason: reason,
                signedEdgeDistance: signedEdgeDistance, horizontalAccuracy: fix.horizontalAccuracy
            )
            return nil
        case .needsCorroboration(let proposed):
            // Cheapest test first: an ambiguous INSIDE cannot move a belief that already says
            // inside, so a second fix would cost a forced request (up to `movementFixRequestTimeout`)
            // to reach `no_change`. A device standing near a boundary hits this on every pass.
            guard await storage.getPolygonMembership()[geofence.id]?.membership != .inside else {
                logger.geofencePolygonUndecided(
                    identifier: geofence.id, reason: PolygonUndecidedReason.corroborationUnnecessary,
                    signedEdgeDistance: signedEdgeDistance, horizontalAccuracy: fix.horizontalAccuracy
                )
                return nil
            }
            guard await corroborate(
                proposed, geofence: geofence, polygon: polygon,
                firstFix: fix, firstEdge: signedEdgeDistance
            ) else { return nil }
            return (proposed, true)
        }
    }

    /// Confirms an arrival that a single fix could not separate from the boundary.
    ///
    /// Requested immediately rather than deferred to a later evaluation: while the device is
    /// stationary there is no later wake, and a pending arrival waiting for one would expire
    /// unresolved in exactly the case this exists to rescue. The process is already awake running
    /// the pass, so the cost is one extra request.
    ///
    /// - Returns: `true` when a second fix independently places the device inside. `false` after
    ///   logging why it did not, so the caller only has to bail out.
    func corroborate(
        _ proposed: PolygonMembership,
        geofence: Geofence,
        polygon: PolygonRegion,
        firstFix: CLLocation,
        firstEdge: Double
    ) async -> Bool {
        guard proposed == .inside else { return false }
        // Newer than the fix being corroborated, which is the only baseline that makes the second
        // fix independent evidence. `resolveFix(requiringFresh:)` alone does NOT give this: it
        // compares against what this resolver last DELIVERED, and a pass answered from
        // `cachedFix` never records there — so CoreLocation echoing that same fix would clear its
        // guard and confirm an arrival against itself.
        let second: CLLocation
        switch await corroborationFix(newerThan: firstFix.timestamp) {
        case .obtained(let fix):
            second = fix
        // Two tokens, not one: an echo means the rule refused to count one fix twice, a timeout
        // means location never answered at all. A capture has to separate them.
        case .notIndependent:
            return refuseFirst(.corroborationNotIndependent, geofence, firstEdge, firstFix)
        case .unavailable:
            return refuseFirst(.noUsableFix, geofence, firstEdge, firstFix)
        }
        let secondPoint = LocationData(
            latitude: second.coordinate.latitude, longitude: second.coordinate.longitude
        )
        let secondEdge = polygon.signedEdgeDistance(to: secondPoint)
        // Three distinct failures, each with its own token. Collapsing them logs a refusal under a
        // reason that did not happen, and these records are how we measure what the rule refuses.
        func refuse(_ reason: PolygonUndecidedReason) -> Bool {
            logger.geofencePolygonUndecided(
                identifier: geofence.id, reason: reason,
                signedEdgeDistance: secondEdge, horizontalAccuracy: second.horizontalAccuracy
            )
            return false
        }
        guard second.horizontalAccuracy > 0 else { return refuse(.noUsableFix) }
        // The second fix must clear the same ceiling, or it adds no information to the first.
        guard second.horizontalAccuracy < polygon.scale else { return refuse(.accuracyTooLow) }
        // Agreement on the SIDE, not on the distance. Two fixes metres apart near a boundary will
        // not agree on an edge, and requiring that would refuse everything this path is for.
        guard secondEdge > 0 else { return refuse(.corroborationDisagreed) }
        return true
    }

    /// One corroboration attempt per judged fix, made on first need and reused.
    ///
    /// Without this, N marginal polygons decided from one fix issue N sequential forced requests,
    /// each able to run to `movementFixRequestTimeout` — a pass under the movement wake's
    /// background-time assertion could then spend most of its budget re-asking the same question.
    /// Reuse is sound only between polygons judged from the SAME fix, which is why the cache is
    /// keyed on `basis` rather than cleared at pass boundaries.
    ///
    /// Logs a corroboration refusal against the FIRST fix's measurements, which are the ones the
    /// caller was judging. Separate from the second-fix refusals below, which carry the second's.
    private func refuseFirst(
        _ reason: PolygonUndecidedReason, _ geofence: Geofence, _ edge: Double, _ fix: CLLocation
    ) -> Bool {
        logger.geofencePolygonUndecided(
            identifier: geofence.id, reason: reason,
            signedEdgeDistance: edge, horizontalAccuracy: fix.horizontalAccuracy
        )
        return false
    }

    /// A refusal is cached alongside a success, including one caused by the resolver TIMING OUT:
    /// a late fix landing in `latestFix` seconds later does not retry this pass. That is
    /// deliberate — the next pass judges a different fix, carries a new basis and asks again — so
    /// do not "fix" this into a retry loop inside a single pass.
    ///
    /// - Parameter basis: timestamp of the fix being corroborated. The answer must strictly
    ///   postdate it; anything at or before it is the first fix over again, not a second opinion.
    func corroborationFix(newerThan basis: Date) async -> CorroborationOutcome {
        if let attempt = passCorroboration, attempt.basis == basis { return attempt.outcome }
        let outcome: CorroborationOutcome
        switch await resolveFix(requiringFresh: true) {
        case .none: outcome = .unavailable
        case .some(let fix): outcome = fix.timestamp > basis ? .obtained(fix) : .notIndependent
        }
        passCorroboration = (basis, outcome)
        return outcome
    }
}
