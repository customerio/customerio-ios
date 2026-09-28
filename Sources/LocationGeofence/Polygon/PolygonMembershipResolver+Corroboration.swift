import CioInternalCommon
import CoreLocation
import Foundation

enum MembershipClassification: Equatable {
    case decided(PolygonMembership)
    /// A marginal inside, held back until the pass's decisive verdicts are in.
    case deferred(PolygonMembership)
    /// Undecided; the reason is already logged.
    case none
}

/// Three cases, not an optional, so a capture can tell an echo of the first fix from no fix.
enum CorroborationOutcome: Equatable {
    case obtained(CLLocation)
    /// A fix came back, but not newer than the one being corroborated.
    case notIndependent
    case unavailable

    var fix: CLLocation? {
        if case .obtained(let fix) = self { return fix }
        return nil
    }
}

extension PolygonMembershipResolver {
    /// A marginal inside is returned, not corroborated here: a second request would age the fix for
    /// every later polygon. Judges on `fix.age` from when the pass chose the fix, not the age now.
    func classifyMembership(
        fix: PassFix,
        geofence: Geofence,
        polygon: PolygonRegion,
        signedEdgeDistance: Double,
        pass: Int
    ) async -> MembershipClassification {
        switch PolygonMembershipDecision.resolvedOutcome(
            signedEdgeDistance: signedEdgeDistance,
            horizontalAccuracy: fix.location.horizontalAccuracy,
            fixAge: fix.age,
            venueScale: polygon.scale
        ) {
        case .decided(let decided):
            return .decided(decided)
        case .undecided(let reason):
            logger.geofencePolygonUndecided(
                identifier: geofence.id, reason: reason,
                signedEdgeDistance: signedEdgeDistance, horizontalAccuracy: fix.location.horizontalAccuracy,
                pass: pass
            )
            return .none
        case .needsCorroboration(let proposed):
            // The already-inside short-circuit is applied later: phase one can still move a belief.
            return .deferred(proposed)
        }
    }

    /// Can only BLOCK a marginal arrival, never gate it. Requested now, not on a later pass: a
    /// stationary device gets no later wake.
    func corroborate(
        _ pending: DeferredCorroboration,
        firstFix: CLLocation,
        cache: PassCorroboration,
        pass: Int
    ) async -> CorroborationResult {
        // Defensive: only a marginal INSIDE is ever deferred.
        guard pending.proposed == .inside else { return .contradicted }
        // Must postdate the first fix. `resolveFix(requiringFresh:)` alone doesn't ensure that: a
        // pass answered from `cachedFix` never records as delivered.
        let second: CLLocation
        switch await corroborationFix(newerThan: firstFix.timestamp, cache: cache) {
        case .obtained(let fix):
            second = fix
        // Neither is evidence the device is outside, so both commit.
        case .notIndependent:
            return .unconfirmed(.corroborationNotIndependent)
        case .unavailable:
            return .unconfirmed(.noUsableFix)
        }
        let secondPoint = LocationData(
            latitude: second.coordinate.latitude, longitude: second.coordinate.longitude
        )
        let secondEdge = pending.polygon.signedEdgeDistance(to: secondPoint)
        // A fix that can't judge this venue doesn't argue against the first, so these commit.
        guard second.horizontalAccuracy > 0 else { return .unconfirmed(.noUsableFix) }
        guard second.horizontalAccuracy < pending.polygon.scale else {
            return .unconfirmed(.accuracyTooLow)
        }
        // Agreement on the SIDE, not the distance.
        guard secondEdge > 0 else {
            logger.geofencePolygonUndecided(
                identifier: pending.geofence.id, reason: .corroborationDisagreed,
                signedEdgeDistance: secondEdge, horizontalAccuracy: second.horizontalAccuracy,
                pass: pass
            )
            return .contradicted
        }
        return .confirmed
    }

    /// A failure, including a timeout, is cached too, so a late fix doesn't retry within this pass.
    func corroborationFix(newerThan basis: Date, cache: PassCorroboration) async -> CorroborationOutcome {
        if let existing = cache.attempt(for: basis) { return existing }
        let outcome: CorroborationOutcome
        switch await resolveFix(requiringFresh: true) {
        case .none: outcome = .unavailable
        case .some(let fix): outcome = fix.timestamp > basis ? .obtained(fix) : .notIndependent
        }
        cache.record(outcome, for: basis)
        return outcome
    }
}

/// Only a second fix that reads OUTSIDE blocks; a missing second opinion commits.
enum CorroborationResult: Equatable {
    case confirmed
    /// No usable second opinion. The arrival still commits.
    case unconfirmed(PolygonUndecidedReason)
    case contradicted
}

/// Owned by the pass, not the resolver: overlapping forced-fresh passes must not reuse each other's
/// attempt.
final class PassCorroboration {
    private var attempt: (basis: Date, outcome: CorroborationOutcome)?

    func attempt(for basis: Date) -> CorroborationOutcome? {
        guard let attempt, attempt.basis == basis else { return nil }
        return attempt.outcome
    }

    func record(_ outcome: CorroborationOutcome, for basis: Date) {
        attempt = (basis, outcome)
    }
}

struct DeferredCorroboration {
    let geofence: Geofence
    let polygon: PolygonRegion
    let signedEdgeDistance: Double
    let proposed: PolygonMembership
}
