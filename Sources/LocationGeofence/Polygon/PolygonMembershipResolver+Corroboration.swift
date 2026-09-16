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
        guard let second = await resolveFix(requiringFresh: true) else {
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
                identifier: geofence.id, reason: PolygonUndecidedReason.withinAccuracy,
                signedEdgeDistance: secondEdge, horizontalAccuracy: second.horizontalAccuracy
            )
            return false
        }
        return true
    }
}
