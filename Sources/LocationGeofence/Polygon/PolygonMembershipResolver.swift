import CioInternalCommon
import CoreLocation
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Turns OS covering-circle events into customer-facing polygon transitions.
///
/// The OS monitors only a polygon's server-guaranteed covering circle, so membership has to be
/// established on device, and this is the only component that owns it. Circle geofences pass
/// straight through; the contradiction gate, baseline heal and dedup baseline know nothing of
/// polygons.
///
/// Invariants, neither to be relaxed:
/// - an ENTER requires a gated fix placing the device inside the polygon;
/// - an EXIT requires a covering-circle exit (polygon ⊆ circle) or a gated fix placing the device
///   outside.
///
/// A fix that cannot decide leaves the stored belief untouched. One deliberate exception on ENTER:
/// a fix inside by LESS than its own accuracy commits unless a usable second fix reads outside
/// (see `PolygonMembershipDecision.resolvedOutcome`). Such a verdict logs `cor=false` with a
/// `corwhy` reason.
///
/// Owns its own `MovementFixResolver`: the transition handler carries only coordinates while the
/// gate needs accuracy and age, and on a wrapper cold wake `CustomerIO.initialize` has not run.
@MainActor
final class PolygonMembershipResolver {
    let storage: GeofenceStorage
    private let transitionEmitter: GeofenceTransitionEmitting
    let fixResolver: MovementFixResolver
    // `internal`, not `private`, only because the split extension files use them.
    let logger: Logger
    let contextStore: BackgroundDeliveryContextStore
    let dateUtil: DateUtil // Fix ages; the replay harness injects a recorded clock.
    let notificationCenter: NotificationCenter
    var foregroundObserverToken: NSObjectProtocol?

    private var passesInFlight = 0
    /// Monotonic, so overlapping passes are distinguishable in a capture: a forced-fresh pass does
    /// not yield to one in flight, so their verdicts can interleave.
    private var passSequence = 0

    private func nextPass() -> Int {
        passSequence += 1
        return passSequence
    }

    init(
        storage: GeofenceStorage,
        transitionEmitter: GeofenceTransitionEmitting,
        logger: Logger,
        contextStore: BackgroundDeliveryContextStore,
        dateUtil: DateUtil = DIGraphShared.shared.dateUtil,
        fixResolver: MovementFixResolver? = nil,
        notificationCenter: NotificationCenter = .default
    ) {
        self.storage = storage
        self.transitionEmitter = transitionEmitter
        self.logger = logger
        self.contextStore = contextStore
        self.dateUtil = dateUtil
        self.notificationCenter = notificationCenter
        // Ten metres, not the circle path's hundred: a verdict needs the device farther from the edge
        // than the fix's accuracy, so a 100 m fix decides nothing for a polygon near minimum size.
        self.fixResolver = fixResolver ?? MovementFixResolver(
            logger: logger,
            backgroundTaskRunner: GeofenceBackgroundTime.runner(name: "io.customer.geofence.polygon-fix"),
            dateUtil: dateUtil,
            desiredAccuracy: kCLLocationAccuracyNearestTenMeters
        )
        registerForegroundEvaluation()
    }

    deinit {
        if let foregroundObserverToken {
            notificationCenter.removeObserver(foregroundObserverToken)
        }
    }

    /// Routes a business-geofence transition the OS delivered. A circle fence is forwarded to the
    /// tracker unchanged; a polygon's covering-circle event is interpreted against membership.
    ///
    /// A geofence missing from the cache (a sync raced this event, or the OS still holds a
    /// condition the cache has dropped) is forwarded as a circle: losing a real crossing is worse
    /// than reporting a covering-circle-shaped one.
    /// - Returns: whether the caller should re-arm the wake, and the fix to size it with.
    @discardableResult
    func handleTransition(
        identifier: String,
        transition: GeofenceTransition,
        occurredAt: Date,
        eventCircle: GeofenceEventCircle = .unknown
    ) async -> PolygonTransitionOutcome {
        guard let geofence = await cachedGeofence(id: identifier), geofence.vertices != nil else {
            // Uncached, or a genuine circle: forward untouched.
            await transitionEmitter.trackTransition(geofenceId: identifier, transition: transition, occurredAt: occurredAt)
            // A circle fence's own event IS the answer, so there is no boundary left to wake for.
            return .nothingToRearm
        }
        switch transition {
        case .exit:
            // No ring needed, but the certainty is polygon ⊆ ITS OWN covering circle, so the write
            // checks the crossed circle is still the fence's. Checked in the write, not here: a
            // refresh landing before the store would otherwise record `outside` for a device
            // inside the replacement polygon.
            //
            // `expired` is refused: the crossed circle is gone, so there is nothing to check
            // against. The next pass re-derives membership.
            switch eventCircle {
            case .circle(let crossed):
                await apply(.outside, to: geofence, evidence: occurredAt, confirmedByFix: false, evaluatedCircle: crossed)
            case .unknown:
                await apply(.outside, to: geofence, evidence: occurredAt, confirmedByFix: false, evaluatedCircle: nil)
            case .expired:
                logger.geofencePolygonUndecided(identifier: identifier, reason: .circleExpired, pass: nil)
            }
            // Boundary now behind us; the next registration re-sizes from wherever the device is.
            return .nothingToRearm
        case .enter:
            guard geofence.polygonRegion != nil else {
                // A stored ring that no longer builds is NOT a circle — forwarding it would fire a
                // customer enter anywhere inside the covering circle.
                logger.geofencePolygonUndecided(identifier: identifier, reason: .ringUnbuildable, pass: nil)
                // No ring means no boundary to size a trigger against either.
                return .nothingToRearm
            }
            // Also a movement event, so the same staleness rule applies as on a wake.
            //
            // No user-switch guard across the fix: the binder captures no expected user for this
            // path. Accepted because the crossing is real and the dedup baseline has already
            // advanced, so declining it loses it for good. The cost: a switch inside the fix
            // window attributes it to the new user.
            //
            // The fix travels out so the caller can re-arm the wake against the polygon boundary.
            guard let fix = await evaluate(geofenceId: identifier, requiresFreshFix: true) else {
                // The pass already recorded why. No fix means nothing to size a trigger with.
                return .nothingToRearm
            }
            return .circleEntered(fix: ResolvedFix(fix))
        }
    }

    /// Re-evaluates membership for polygons that have just been registered, where the device may
    /// already be standing inside and no crossing will ever be delivered.
    ///
    /// One fix serves the whole batch: resolving per geofence would spend a timed request per
    /// polygon on the main actor whenever the cache stays empty.
    ///
    /// Each request is logged because this path bypasses `handleTransition`, so nothing else
    /// records that a re-check was asked for.
    ///
    /// `isStillCurrent` is re-checked after the fix resolves: a user switch during that await
    /// clears user-scoped state, and resuming would rewrite the old user's belief.
    /// - Returns: whether a usable fix was obtained, so a caller that owes a verdict can retry on
    /// other terms. True when there was nothing to evaluate.
    @discardableResult
    func evaluateMembership(
        geofenceIds: [String],
        reason: PolygonEvaluationReason,
        requiresFreshFix: Bool = false,
        isStillCurrent: (@Sendable () -> Bool)? = nil
    ) async -> Bool {
        for geofenceId in geofenceIds {
            logger.geofencePolygonEvaluationRequested(identifier: geofenceId, reason: reason)
        }
        // Ids, never rings: one fix serves the batch, and the ring each verdict uses is read after
        // that fix inside `evaluate`, so a refresh landing mid-request cannot be decided against.
        var pending: [String] = []
        for geofenceId in geofenceIds {
            // Builds the ring, not just the `vertices` check the whole-set pass uses, so an
            // unbuildable ring is dropped before a fix request is spent on it.
            guard let geofence = await cachedGeofence(id: geofenceId), geofence.polygonRegion != nil
            else { continue }
            pending.append(geofenceId)
        }
        guard !pending.isEmpty else { return true }
        let pass = nextPass()
        logger.geofencePolygonPassStarted(reason: reason, count: pending.count, pass: pass)
        guard let fix = await requestedPassFix(requiringFresh: requiresFreshFix) else {
            for geofenceId in pending {
                logger.geofencePolygonUndecided(identifier: geofenceId, reason: .noUsableFix, pass: pass)
            }
            return false
        }
        await runPass(geofenceIds: pending, fix: fix, pass: pass, isStillCurrent: isStillCurrent)
        return true
    }

    /// Re-evaluates every registered polygon against one fix. Runs on foreground, movement wakes
    /// and visits: a device already inside a polygon when monitoring began has crossed nothing, so
    /// no OS event will report it.
    ///
    /// A pass already in flight wins unless this one requires a fresh fix. Foregrounds arrive in
    /// bursts and a second scan would only repeat the work, but a wake runs BECAUSE the device
    /// moved, so it never yields. Its request still coalesces inside `MovementFixResolver` with
    /// any already in flight, so it may be answered by a fix that predates its own crossing.
    func evaluateAllPolygons(
        reason: PolygonEvaluationReason,
        requiresFreshFix: Bool = false,
        heldFix: ResolvedFix? = nil,
        isStillCurrent: (@Sendable () -> Bool)? = nil
    ) async {
        if passesInFlight > 0, !requiresFreshFix {
            logger.geofencePolygonPassSkipped(reason: .passInFlight)
            return
        }
        passesInFlight += 1
        defer { passesInFlight -= 1 }
        let registered = await storage.getRegisteredBusinessIds()
        let polygons = await storage.getCachedGeofences()
            .filter { registered.contains($0.id) && $0.vertices != nil }
        // Before the empty guard on purpose: `n=0` is the record that a pass ran and had nothing
        // to judge, which is otherwise a silent return.
        let pass = nextPass()
        let heldFixDecision = heldFixUse(heldFix)
        logger.geofencePolygonPassStarted(reason: reason, count: polygons.count, pass: pass, heldFix: heldFixDecision.use)
        guard polygons.isEmpty == false else { return }
        // At most one request for the whole pass: per-polygon requests would hold the main actor
        // for a timeout each when the cache stays empty, and a failed fresh request would silently
        // downgrade every later polygon to the pre-wake fix.
        guard let fix = await passFix(heldFix: heldFix, decision: heldFixDecision, requiringFresh: requiresFreshFix) else {
            for geofence in polygons {
                logger.geofencePolygonUndecided(identifier: geofence.id, reason: .noUsableFix, pass: pass)
            }
            return
        }
        await runPass(geofenceIds: polygons.map(\.id), fix: fix, pass: pass, isStillCurrent: isStillCurrent)
    }

    /// - Returns: the fix the pass ran against, or nil when none could be obtained.
    @discardableResult
    private func evaluate(
        geofenceId: String,
        requiresFreshFix: Bool = false,
        isStillCurrent: (@Sendable () -> Bool)? = nil
    ) async -> CLLocation? {
        let pass = nextPass()
        logger.geofencePolygonPassStarted(reason: .osTransition, count: 1, pass: pass)
        guard let fix = await requestedPassFix(requiringFresh: requiresFreshFix) else {
            logger.geofencePolygonUndecided(identifier: geofenceId, reason: .noUsableFix, pass: pass)
            return nil
        }
        await runPass(geofenceIds: [geofenceId], fix: fix, pass: pass, isStillCurrent: isStillCurrent)
        return fix.location
    }

    /// Takes an id, never a caller's `PolygonRegion`: resolving a fix suspends, and a refresh can
    /// replace the fence under the same id meanwhile. The ring and the registration are re-read
    /// here from one load, so the verdict uses current geometry and a fence unregistered during
    /// the fix is not judged. That costs one state decode per polygon; a single up-front snapshot
    /// would make every verdict a whole location request stale.
    /// - Returns: a marginal arrival to corroborate in the pass's second phase, or nil when the
    ///   fix settled it or settled nothing.
    func evaluate(
        geofenceId: String,
        fix: PassFix,
        pass: Int,
        isStillCurrent: (@Sendable () -> Bool)? = nil
    ) async -> DeferredCorroboration? {
        guard CLLocationCoordinate2DIsValid(fix.location.coordinate) else {
            logger.geofencePolygonUndecided(identifier: geofenceId, reason: .noUsableFix, pass: pass)
            return nil
        }
        if let isStillCurrent, !isStillCurrent() {
            logger.geofencePolygonUndecided(identifier: geofenceId, reason: .userChanged, pass: pass)
            return nil
        }
        guard let geofence = await storage.getRegisteredGeofence(id: geofenceId),
              let polygon = geofence.polygonRegion
        else {
            logger.geofencePolygonUndecided(identifier: geofenceId, reason: .unregistered, pass: pass)
            return nil
        }
        let point = LocationData(latitude: fix.location.coordinate.latitude, longitude: fix.location.coordinate.longitude)
        let signedEdgeDistance = polygon.signedEdgeDistance(to: point)
        switch await classifyMembership(
            fix: fix, geofence: geofence, polygon: polygon,
            signedEdgeDistance: signedEdgeDistance, pass: pass
        ) {
        case .none:
            return nil
        case .deferred(let proposed):
            return DeferredCorroboration(
                geofence: geofence, polygon: polygon,
                signedEdgeDistance: signedEdgeDistance, proposed: proposed
            )
        case .decided(let membership):
            await record(
                PolygonVerdict(
                    membership: membership, corroboration: .notNeeded,
                    signedEdgeDistance: signedEdgeDistance, pass: pass
                ),
                for: geofence, fix: fix.location, isStillCurrent: isStillCurrent
            )
            return nil
        }
    }

    /// Applies a membership verdict and delivers the crossing when it changes the stored belief.
    ///
    /// `evidence` is when the crossing happened: a fix's timestamp, or the OS event's date for a
    /// covering-circle exit. It orders the write against the stored belief and stamps the event.
    /// `confirmedByFix` says which of the two it was, for the log.
    ///
    /// `evaluatedRing` / `evaluatedCircle` are the geometry the verdict rests on, and the write is
    /// refused if the fence has moved off it since. A fix verdict passes the ring; a covering-circle
    /// exit passes the circle it crossed, when known.
    ///
    /// `isStillCurrent` is checked immediately before the emit, with no await after it. The write
    /// is unguarded on purpose: a belief is geometry, true whoever is signed in, while the emit
    /// attributes it to a user.
    ///
    /// `internal` only because the pass runner lives in a split file.
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
        await transitionEmitter.trackTransition(geofenceId: geofence.id, transition: transition, occurredAt: evidence)
    }

    private func cachedGeofence(id: String) async -> Geofence? {
        await storage.getCachedGeofences().first { $0.id == id }
    }
}
