import CioInternalCommon
import CoreLocation
import Foundation

/// What one fix alone established about a polygon, before any second fix is spent.
enum MembershipClassification: Equatable {
    case decided(PolygonMembership)
    /// A marginal inside, worth a second fix — held back until the pass's decisive verdicts are in.
    case deferred(PolygonMembership)
    /// Nothing, and the reason is already logged.
    case none
}

/// What a corroboration attempt yielded. Three cases, not an optional, so a capture can tell an
/// echo of the first fix from no fix at all.
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

/// The second-fix confirmation for a marginal arrival, split from the resolver's core for the file
/// cap. Members are `internal` only because of the split.
extension PolygonMembershipResolver {
    /// Applies the arrival rule to one fix WITHOUT spending a second one.
    ///
    /// A marginal inside is RETURNED rather than corroborated here: a corroboration request can
    /// take up to `movementFixRequestTimeout`, aging the fix for every polygon judged after it. The
    /// caller settles everything the fix alone can decide first and corroborates afterwards.
    ///
    /// Judges on `fix.age`, the age settled when the pass chose the fix, not the age now: re-reading
    /// the clock mid-pass would push a fix near `movementFixMaxAge` over it for later polygons.
    /// - Returns: what the fix alone establishes, after logging why it established nothing.
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
            // The already-inside short-circuit is applied later, right before the request it saves:
            // phase one can move a belief after this point.
            return .deferred(proposed)
        }
    }

    /// Seeks a second fix for an arrival a single fix could not separate from the boundary. It can
    /// only BLOCK the arrival, never gate it.
    ///
    /// Requested now rather than on a later evaluation: a stationary device gets no later wake, so
    /// a pending arrival would never resolve.
    ///
    /// - Returns: whether a second fix confirmed the arrival, could not be obtained, or
    ///   contradicted it. Only the last blocks delivery.
    func corroborate(
        _ pending: DeferredCorroboration,
        firstFix: CLLocation,
        cache: PassCorroboration,
        pass: Int
    ) async -> CorroborationResult {
        // Defensive: only a marginal INSIDE is ever deferred, and nothing else may commit here.
        guard pending.proposed == .inside else { return .contradicted }
        // Must postdate the fix being corroborated to be independent evidence.
        // `resolveFix(requiringFresh:)` alone does NOT ensure that: it compares against what this
        // resolver last DELIVERED, and a pass answered from `cachedFix` never records there, so an
        // echo of that fix would confirm the arrival against itself.
        let second: CLLocation
        switch await corroborationFix(newerThan: firstFix.timestamp, cache: cache) {
        case .obtained(let fix):
            second = fix
        // Separate tokens so a capture can tell an echo from no answer. Neither is evidence the
        // device is outside, so both commit.
        case .notIndependent:
            return .unconfirmed(.corroborationNotIndependent)
        case .unavailable:
            return .unconfirmed(.noUsableFix)
        }
        let secondPoint = LocationData(
            latitude: second.coordinate.latitude, longitude: second.coordinate.longitude
        )
        let secondEdge = pending.polygon.signedEdgeDistance(to: secondPoint)
        // A fix that cannot judge this venue adds nothing but does not argue against the first,
        // so these commit with the reason on the verdict.
        guard second.horizontalAccuracy > 0 else { return .unconfirmed(.noUsableFix) }
        guard second.horizontalAccuracy < pending.polygon.scale else {
            return .unconfirmed(.accuracyTooLow)
        }
        // Agreement on the SIDE, not the distance: two fixes metres apart near a boundary will
        // not agree on an edge.
        //
        // The one blocking outcome, logged here because it is the only branch with no verdict.
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

    /// One corroboration attempt per judged fix, made on first need and reused, so N marginal
    /// polygons judged from one fix cost one request instead of N sequential timeouts.
    ///
    /// A failure is cached too, including a timeout, so a late fix does not retry within this pass.
    /// Cheap, because an unanswered attempt still commits the arrival as `unconfirmed`.
    ///
    /// - Parameter basis: timestamp of the fix being corroborated. The answer must strictly
    ///   postdate it; anything at or before it is the first fix over again.
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

/// What a corroboration attempt settled for a marginal arrival. Only a second fix that reads
/// OUTSIDE blocks; a missing second opinion commits and records why it could not be confirmed.
enum CorroborationResult: Equatable {
    /// A second, independent fix agreed.
    case confirmed
    /// No usable second opinion. The arrival still commits; the reason rides on the verdict.
    case unconfirmed(PolygonUndecidedReason)
    /// A second fix placed the device on the other side of the boundary.
    case contradicted
}

/// One corroboration attempt per pass, so N marginal polygons sharing a fix cost one request.
///
/// Owned by the pass, not the resolver: two forced-fresh passes can overlap (one refresh starts
/// both `evaluateNewlyRegistered` and the movement pass), and shared state would let one pass
/// reuse an attempt the other made. The `basis` key stops an attempt answering for a fix it
/// predates.
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

/// A marginal arrival held back until every polygon the pass fix could decide on its own has been.
struct DeferredCorroboration {
    let geofence: Geofence
    let polygon: PolygonRegion
    let signedEdgeDistance: Double
    let proposed: PolygonMembership
}
