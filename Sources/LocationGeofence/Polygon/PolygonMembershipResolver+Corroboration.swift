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
    /// Applies the arrival rule to one fix WITHOUT spending a second one.
    ///
    /// A marginal inside is RETURNED rather than corroborated here: a corroboration request can
    /// burn its full `movementFixRequestTimeout` mid-pass, and every polygon judged after it would
    /// get the same fix that much older. The caller decides everything the fix alone can settle
    /// first and corroborates afterwards.
    ///
    /// - Returns: what the fix alone establishes, after logging why it established nothing.
    /// - Parameter fixAge: the age the PASS settled on, not the age right now. One fix serves the
    ///   whole pass, so its usability is decided once. Recomputing here re-asks a question already
    ///   answered and can answer it differently part-way through: a fix taken just inside
    ///   `movementFixMaxAge` crosses the limit while the pass runs, and every polygon after that
    ///   records `fix_too_old` even though the pass began with a fix it was entitled to use.
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
            // The already-inside short-circuit is NOT applied here. It has to be read immediately
            // before the request it saves, and phase one can move a belief after this point.
            return .deferred(proposed)
        }
    }

    /// Seeks a second opinion on an arrival that a single fix could not separate from the
    /// boundary — and can only ever BLOCK it, never gate it.
    ///
    /// Requested immediately rather than deferred to a later evaluation: while the device is
    /// stationary there is no later wake, and a pending arrival waiting for one would expire
    /// unresolved in exactly the case this exists to rescue. The process is already awake running
    /// the pass, so the cost is one extra request.
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
        // Newer than the fix being corroborated, which is the only baseline that makes the second
        // fix independent evidence. `resolveFix(requiringFresh:)` alone does NOT give this: it
        // compares against what this resolver last DELIVERED, and a pass answered from
        // `cachedFix` never records there — so CoreLocation echoing that same fix would clear its
        // guard and confirm an arrival against itself.
        let second: CLLocation
        switch await corroborationFix(newerThan: firstFix.timestamp, cache: cache) {
        case .obtained(let fix):
            second = fix
        // Two tokens, not one: an echo means the rule declined to count one fix twice, a timeout
        // means location never answered at all. A capture has to separate them. Neither is
        // evidence the device is outside, so both commit.
        case .notIndependent:
            return .unconfirmed(.corroborationNotIndependent)
        case .unavailable:
            return .unconfirmed(.noUsableFix)
        }
        let secondPoint = LocationData(
            latitude: second.coordinate.latitude, longitude: second.coordinate.longitude
        )
        let secondEdge = pending.polygon.signedEdgeDistance(to: secondPoint)
        // A fix that cannot judge this venue adds nothing to the first, which is not the same as
        // arguing against it — so these commit, carrying the reason onto the verdict.
        guard second.horizontalAccuracy > 0 else { return .unconfirmed(.noUsableFix) }
        guard second.horizontalAccuracy < pending.polygon.scale else {
            return .unconfirmed(.accuracyTooLow)
        }
        // Agreement on the SIDE, not on the distance. Two fixes metres apart near a boundary will
        // not agree on an edge, and requiring that would refuse everything this path is for.
        //
        // The one blocking outcome: a usable second fix that reads the other side. Logged here
        // because it is the only branch that produces no verdict of its own.
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

    /// One corroboration attempt per judged fix, made on first need and reused.
    ///
    /// Without this, N marginal polygons decided from one fix issue N sequential forced requests,
    /// each able to run to `movementFixRequestTimeout` — a pass under the movement wake's
    /// background-time assertion could then spend most of its budget re-asking the same question.
    /// Reuse is sound only between polygons judged from the SAME fix, which is why the cache is
    /// keyed on `basis` rather than cleared at pass boundaries.
    ///
    /// A failure is cached alongside a success, including one caused by the resolver TIMING OUT:
    /// a late fix landing in `latestFix` seconds later does not retry within this pass. Cheap,
    /// because an unanswered attempt no longer refuses the arrival — it commits it as
    /// `unconfirmed` — so the cached failure costs a confirmation, never a visit.
    ///
    /// - Parameter basis: timestamp of the fix being corroborated. The answer must strictly
    ///   postdate it; anything at or before it is the first fix over again, not a second opinion.
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

/// What a corroboration attempt settled for a marginal arrival.
///
/// Absence of a second opinion is NOT an argument against the first fix. While the device stands
/// still nothing re-derives a missed arrival, so refusing one loses the visit outright; a spurious
/// arrival is corrected by the next decisive fix. Only a second fix that positively reads OUTSIDE
/// blocks — every other outcome commits and records why it could not be confirmed.
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
/// Owned by the pass rather than the resolver, and that is the whole point. Two `requiresFreshFix`
/// passes overlap by design — one refresh starts both `evaluateNewlyRegistered` and the movement
/// pass, and the in-flight guard deliberately lets a fresh pass through. Resolver-level state keyed
/// only on the fix timestamp therefore let ONE pass's timed-out request answer the OTHER pass
/// judging that same fix, which never then made an attempt of its own: a transient timeout
/// suppressed an arrival. A pass cannot reuse an attempt it did not make.
///
/// The basis key is kept for correctness within the pass — an attempt must never answer for a fix
/// it predates — but it is no longer load-bearing for liveness.
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
