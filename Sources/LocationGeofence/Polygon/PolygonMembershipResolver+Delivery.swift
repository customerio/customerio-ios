import CioInternalCommon
import CoreLocation
import Foundation

/// Applying verdicts and routing circle events to the dwell coordinator and the tracker, split
/// from the resolver's core so both stay under the file cap. The members it reads are `internal`
/// rather than `private` only because of this split; they remain implementation detail.
@MainActor
extension PolygonMembershipResolver {
    /// Applies a membership verdict and delivers the crossing when it changes the stored belief.
    /// `evidence` is when the crossing happened — a fix's timestamp, or the OS event's date for a
    /// covering-circle exit. Required, not optional: it both orders the write against the stored
    /// belief and stamps the event, so omitting it would write an unordered belief AND report the
    /// delivery time as the crossing — here a whole forced-fresh fix request later. `confirmedByFix`
    /// says which of the two dates it was; the date alone cannot tell the log how it was decided.
    ///
    /// `isStillCurrent` is re-checked here, immediately before the emit and with no await after it:
    /// the tracker stamps whoever is current when it is entered, and the write below is an await of
    /// its own. The write is left unguarded deliberately — a belief states geometry, true whoever
    /// is signed in; an emit is an ATTRIBUTION, and attribution is what a switch invalidates.
    ///
    /// `internal` rather than `private` only because the pass runner lives in a split file.
    ///
    /// `evaluatedRing` is the geometry the verdict was computed from, and the write is refused if
    /// the workspace has moved off it since. Nil from the covering-circle exit, and that is not an
    /// omission: polygon ⊆ circle holds for whatever ring is current, so leaving the circle is a
    /// verdict no replacement can invalidate. Only a ring-derived verdict can go stale with the ring.
    func apply(
        _ membership: PolygonMembership,
        to geofence: Geofence,
        evidence: Date,
        confirmedByFix: Bool,
        evaluatedRing: [LocationData]? = nil,
        evaluatedCircle: MonitoredCircle? = nil,
        isStillCurrent: (@Sendable () -> Bool)? = nil
    ) async {
        let outcome = await storage.recordPolygonMembership(
            membership,
            forIdentifier: geofence.id,
            onlyIfBeliefPredates: evidence,
            onlyIfRingMatches: evaluatedRing,
            onlyIfCircleMatches: evaluatedCircle
        )
        var exitContext: GeofenceExitContext?
        let expectedUserId = contextStore.currentUserId
        if isStillCurrent?() ?? true {
            exitContext = await forwardDwellEvidence(
                PolygonDwellEvidence(membership: membership, outcome: outcome),
                geofence: geofence, at: evidence, confirmedByFix: confirmedByFix,
                expectedUserId: expectedUserId
            )
        }
        guard case .deliver(let transition) = outcome else {
            logger.geofencePolygonNotDelivered(identifier: geofence.id, reason: .outcome(outcome))
            return
        }
        guard geofence.transitionTypes.contains(transition) else {
            logger.geofencePolygonNotDelivered(identifier: geofence.id, reason: .transitionNotRegistered)
            return
        }
        if let isStillCurrent, !isStillCurrent() {
            logger.geofencePolygonNotDelivered(identifier: geofence.id, reason: .userChanged)
            return
        }
        logger.geofencePolygonTransition(identifier: geofence.id, transition: transition, confirmedByFix: confirmedByFix)
        await emitPolygonTransition(
            transition, geofenceId: geofence.id, occurredAt: evidence,
            exitContext: exitContext, expectedUserId: expectedUserId
        )
    }

    /// Read synchronously by the OS callback, so crossings are attributed to whoever was
    /// identified when they were delivered rather than when their dispatch task ran. Nonisolated
    /// because that callback is not main-actor isolated; the context store is thread-safe.
    nonisolated var identifiedUserId: String? {
        contextStore.currentUserId
    }

    /// A polygon's covering-circle EXIT. No ring needed — leaving a circle says nothing about a
    /// ring — but the certainty is polygon ⊆ ITS OWN covering circle, so the crossed circle has to
    /// still be the fence's. That is checked inside the write, not here: a refresh landing between
    /// this hop and the store would otherwise leave `outside` recorded for a device inside the
    /// replacement polygon, stamped with a date no older fix can correct.
    ///
    /// `expired` is refused rather than forwarded: the circle crossed is gone, so the write has
    /// nothing to check the ring against, and "cannot say" would store `outside` for a device
    /// inside the replacement polygon. The next pass re-derives it.
    func applyCoveringCircleExit(geofence: Geofence, eventCircle: GeofenceEventCircle, occurredAt: Date) async {
        switch eventCircle {
        case .circle(let crossed):
            await apply(.outside, to: geofence, evidence: occurredAt, confirmedByFix: false, evaluatedCircle: crossed)
        case .unknown:
            await apply(.outside, to: geofence, evidence: occurredAt, confirmedByFix: false, evaluatedCircle: nil)
        case .expired:
            logger.geofencePolygonUndecided(identifier: geofence.id, reason: .circleExpired, pass: nil)
        }
    }

    /// A circle fence's OS event, forwarded untouched apart from the visit it opens or closes.
    /// `receivedForUserId` is who was identified when the OS delivered it; see `handleTransition`.
    ///
    /// An ENTER's visit is written ALONGSIDE its delivery, neither awaiting the other. Awaiting the
    /// visit first put a storage round trip before the user check, and a sign-out landing in it
    /// dropped the crossing itself. Awaiting the delivery first put the whole send — HTTP, backlog
    /// flush, an offline timeout — before the write, so an EXIT in that window found no visit and a
    /// write landing after it left one open for a device already outside. The child task needs the
    /// main actor, which this function holds until `forwardEnter` suspends inside the tracker, so the
    /// ENTER's user check still runs first. An EXIT overtaking the write is caught by the dwell
    /// coordinator, which refuses a visit that started before an EXIT it has seen.
    ///
    /// An EXIT has to read its visit first — the duration travels on the event — and is bound to
    /// the receiving user, so a switch meanwhile drops rather than misattributes it.
    func forwardCircleTransition(
        geofence: Geofence,
        transition: GeofenceTransition,
        occurredAt: Date,
        receivedForUserId: String
    ) async {
        switch transition {
        case .enter:
            let dwellCoordinator = dwellCoordinator
            async let visitRecorded: GeofenceExitContext? = dwellCoordinator?.handleBoundary(
                geofence: geofence, transition: .enter, occurredAt: occurredAt, expectedUserId: receivedForUserId
            )
            if geofence.transitionTypes.contains(.enter) {
                await forwardEnter(identifier: geofence.id, occurredAt: occurredAt, receivedForUserId: receivedForUserId)
            }
            _ = await visitRecorded
        case .exit:
            let exitContext = await dwellCoordinator?.handleBoundary(
                geofence: geofence, transition: .exit, occurredAt: occurredAt, expectedUserId: receivedForUserId
            )
            guard geofence.transitionTypes.contains(.exit) else { return }
            await transitionEmitter.trackExit(
                geofenceId: geofence.id, occurredAt: occurredAt, context: exitContext,
                expectedUserId: receivedForUserId
            )
        case .dwell:
            // Core Location never produces one; dwell is the coordinator's own decision.
            return
        }
    }

    /// An OS event for a fence the cache no longer holds, forwarded as the circle it predates
    /// polygons as. No visit: there is no fence to measure against.
    ///
    /// `unconfigured` is the one piece of configuration that outlives the cache: the edges the
    /// circle was registered for only as visit bookkeeping (an exit-only or dwell-only circle is
    /// registered for ENTER too). Those are dropped — the customer never asked for them. Every
    /// other edge is forwarded unfiltered, as before, so a configured ENTER still arrives.
    func forwardUncachedTransition(
        identifier: String,
        transition: GeofenceTransition,
        occurredAt: Date,
        receivedForUserId: String,
        unconfigured: Set<GeofenceTransition> = []
    ) async {
        guard !unconfigured.contains(transition) else {
            logger.geofenceCallbackDropped(identifier: identifier, transition: transition, reason: "transition_not_configured")
            return
        }
        switch transition {
        case .enter:
            await forwardEnter(identifier: identifier, occurredAt: occurredAt, receivedForUserId: receivedForUserId)
        case .exit:
            await transitionEmitter.trackExit(
                geofenceId: identifier, occurredAt: occurredAt, context: nil, expectedUserId: receivedForUserId
            )
        case .dwell:
            return
        }
    }

    /// ENTER carries no visit context, so the receiving user is checked here rather than by the
    /// tracker: a switch since the OS delivered it must not stamp the crossing to the next user.
    private func forwardEnter(identifier: String, occurredAt: Date, receivedForUserId: String) async {
        guard (contextStore.currentUserId ?? "") == receivedForUserId else {
            logger.geofenceCallbackDropped(identifier: identifier, transition: .enter, reason: "user_changed")
            return
        }
        await transitionEmitter.trackTransition(geofenceId: identifier, transition: .enter, occurredAt: occurredAt)
    }

    /// Hands a real-shape verdict to the dwell coordinator. Returns the visit an EXIT closed, to
    /// travel with that EXIT; nil for every other verdict.
    private func forwardDwellEvidence(
        _ dwellEvidence: PolygonDwellEvidence,
        geofence: Geofence,
        at evidence: Date,
        confirmedByFix: Bool,
        expectedUserId: String?
    ) async -> GeofenceExitContext? {
        switch dwellEvidence {
        case .entered, .stillInside:
            await dwellCoordinator?.recordInsideEvidence(
                geofence: geofence,
                at: evidence,
                source: "location_evidence",
                expectedUserId: expectedUserId,
                beginsNewVisit: dwellEvidence == .entered
            )
            return nil
        case .exited:
            return await dwellCoordinator?.handleBoundary(
                geofence: geofence,
                transition: .exit,
                occurredAt: evidence,
                expectedUserId: expectedUserId,
                detectionSource: confirmedByFix ? "location_evidence" : "covering_circle"
            )
        case .none:
            return nil
        }
    }

    private func emitPolygonTransition(
        _ transition: GeofenceTransition,
        geofenceId: String,
        occurredAt: Date,
        exitContext: GeofenceExitContext?,
        expectedUserId: String?
    ) async {
        if transition == .exit {
            await transitionEmitter.trackExit(
                geofenceId: geofenceId, occurredAt: occurredAt, context: exitContext,
                expectedUserId: expectedUserId
            )
        } else {
            await transitionEmitter.trackTransition(
                geofenceId: geofenceId, transition: transition, occurredAt: occurredAt
            )
        }
    }
}

/// What a membership write means for the dwell visit. Only a write that established or confirmed
/// inside, or delivered an EXIT, is evidence; every other outcome leaves the visit alone.
private enum PolygonDwellEvidence: Equatable {
    case entered
    case stillInside
    case exited
    case none

    init(membership: PolygonMembership, outcome: PolygonMembershipOutcome) {
        switch (membership, outcome) {
        case (.inside, .deliver(.enter)): self = .entered
        case (.inside, .suppressedNoChange): self = .stillInside
        case (.outside, .deliver(.exit)): self = .exited
        default: self = .none
        }
    }
}
