import CioInternalCommon
import CoreLocation
import Foundation

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
                firstEdge: signedEdgeDistance, firstAccuracy: fix.horizontalAccuracy
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
        firstEdge: Double,
        firstAccuracy: Double
    ) async -> Bool {
        guard proposed == .inside else { return false }
        guard let second = await corroborationFix() else {
            logger.geofencePolygonUndecided(
                identifier: geofence.id, reason: PolygonUndecidedReason.noUsableFix,
                signedEdgeDistance: firstEdge, horizontalAccuracy: firstAccuracy
            )
            return false
        }
        let secondPoint = LocationData(
            latitude: second.coordinate.latitude, longitude: second.coordinate.longitude
        )
        let secondEdge = polygon.signedEdgeDistance(to: secondPoint)
        // Agreement on the SIDE, not on the distance. Two fixes metres apart near a boundary will
        // not agree on an edge, and requiring that would refuse everything this path is for.
        // The second fix must clear the same ceiling, or it adds no information to the first.
        guard secondEdge > 0, second.horizontalAccuracy > 0,
              second.horizontalAccuracy < polygon.scale
        else {
            logger.geofencePolygonUndecided(
                identifier: geofence.id,
                // Two distinct failures, and the token has to tell them apart: the second fix
                // disagreed about the side, or it was too coarse for this venue at all.
                reason: second.horizontalAccuracy < polygon.scale
                    ? PolygonUndecidedReason.withinAccuracy
                    : PolygonUndecidedReason.accuracyTooLow,
                signedEdgeDistance: secondEdge, horizontalAccuracy: second.horizontalAccuracy
            )
            return false
        }
        return true
    }

    /// One corroboration fix per pass, resolved on first need and reused.
    ///
    /// Without this, N marginal polygons in one pass issue N sequential forced requests, each able
    /// to run to `movementFixRequestTimeout` — a pass under the movement wake's background-time
    /// assertion could then spend most of its budget re-asking the same question. Reuse is sound
    /// because the property corroboration needs is that the second fix is STRICTLY NEWER than the
    /// pass's own fix, which `resolveFix(requiringFresh:)` already guarantees; it does not need to
    /// be per-polygon.
    func corroborationFix() async -> CLLocation? {
        if let cached = passCorroborationFix { return cached }
        let resolved = await resolveFix(requiringFresh: true)
        passCorroborationFix = resolved
        return resolved
    }
}
