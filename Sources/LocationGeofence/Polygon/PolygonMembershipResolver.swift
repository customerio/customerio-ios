import CioInternalCommon
import CoreLocation
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Turns OS covering-circle events into customer-facing polygon transitions.
///
/// The OS monitors a polygon's server-guaranteed covering circle and knows nothing about the
/// polygon itself, so membership is a second fact that has to be established on device. This sits
/// between the monitor and the event tracker and is the only component that owns it. Circle
/// geofences pass straight through: the contradiction gate, baseline heal and dedup baseline that
/// serve them are deliberately left unaware polygons exist.
///
/// Two invariants define correctness here, and neither may be relaxed:
/// - an ENTER requires a gated fix placing the device inside the polygon;
/// - an EXIT requires either a covering-circle exit — polygon ⊆ circle, so leaving the circle
///   provably leaves the polygon — or a gated fix placing the device outside.
///
/// Everything else is silent. That is what "no event without gated geometric confirmation" means
/// in code, and why an undecidable fix leaves the stored belief untouched rather than guessing.
///
/// Owns its own `MovementFixResolver` rather than reading the monitor's: the transition handler
/// carries only coordinates, while the gate needs accuracy and age, and on a wrapper cold wake
/// `CustomerIO.initialize` has not run — the same reasoning that gives each monitor its own.
@MainActor
final class PolygonMembershipResolver {
    private let storage: GeofenceStorage
    private let transitionEmitter: GeofenceTransitionEmitting
    private let fixResolver: MovementFixResolver
    private let logger: Logger
    private let contextStore: BackgroundDeliveryContextStore
    private let notificationCenter: NotificationCenter
    private var foregroundObserverToken: NSObjectProtocol?
    private var isEvaluatingAllPolygons = false

    init(
        storage: GeofenceStorage,
        transitionEmitter: GeofenceTransitionEmitting,
        logger: Logger,
        contextStore: BackgroundDeliveryContextStore,
        fixResolver: MovementFixResolver? = nil,
        notificationCenter: NotificationCenter = .default
    ) {
        self.storage = storage
        self.transitionEmitter = transitionEmitter
        self.logger = logger
        self.contextStore = contextStore
        self.notificationCenter = notificationCenter
        // Ten metres, not the hundred the circle path uses: a verdict needs the device farther from
        // the boundary than the fix is accurate, so a hundred-metre fix cannot decide anything for a
        // polygon near the minimum monitored size.
        self.fixResolver = fixResolver ?? MovementFixResolver(
            logger: logger,
            backgroundTaskRunner: GeofenceBackgroundTime.runner(name: "io.customer.geofence.polygon-fix"),
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
    /// condition the cache has dropped) is forwarded rather than dropped: treating it as a circle
    /// is the behaviour that predates polygons, and losing a real crossing is worse than a
    /// covering-circle-shaped one.
    func handleTransition(
        identifier: String,
        transition: GeofenceTransition,
        occurredAt: Date,
        eventCircle: MonitoredCircle? = nil
    ) async {
        guard let geofence = await cachedGeofence(id: identifier), geofence.vertices != nil else {
            // Uncached, or a genuine circle: forward untouched, the behaviour that predates polygons.
            await transitionEmitter.trackTransition(geofenceId: identifier, transition: transition)
            return
        }
        switch transition {
        case .exit:
            // No ring needed — leaving a circle says nothing about a ring — but the certainty is
            // polygon ⊆ ITS OWN covering circle, so the crossed circle has to still be the fence's.
            // That is checked inside the write, not here: a refresh landing between this hop and
            // the store would otherwise leave `outside` recorded for a device inside the
            // replacement polygon, stamped with a date no older fix can correct. A nil circle means
            // the producer could not say which one was crossed, and is treated as current.
            await apply(
                .outside, to: geofence, evidence: occurredAt,
                confirmedByFix: false, evaluatedCircle: eventCircle
            )
        case .enter:
            guard geofence.polygonRegion != nil else {
                // A stored ring that no longer builds is NOT a circle — forwarding it would fire a
                // customer enter anywhere inside the covering circle.
                logger.geofencePolygonUndecided(identifier: identifier, reason: "stored ring no longer builds")
                return
            }
            // Also a movement event, so the same staleness rule applies as on a wake.
            //
            // No user boundary across the fix, unlike `evaluateMembership`, and none exists to
            // carry: the binder dispatches this with no expected user captured anywhere. Accepted
            // on the trade this file makes elsewhere — the crossing is geometrically real, and
            // declining it loses it for good because the dedup baseline has already advanced. The
            // cost is real: a switch inside the fix window attributes it to a user who may not
            // monitor this polygon at all.
            await evaluate(geofenceId: identifier, requiresFreshFix: true)
        }
    }

    /// Re-evaluates membership for polygons that have just been registered, where the device may
    /// already be standing inside and no crossing will ever be delivered. A geofence that is no
    /// longer cached or no longer a polygon has nothing to decide.
    ///
    /// One fix serves the whole batch, for the same reason the foreground pass shares one: resolving
    /// per geofence issues a fresh timed request each time the cache stays empty, and a registration
    /// carrying several new polygons would spend that timeout once per polygon on the main actor.
    ///
    /// Logged because this path bypasses `handleTransition`, so nothing else records that we were
    /// asked to re-check. Reading the absence of a log line as an absence of evaluations led to
    /// exactly the wrong conclusion once already.
    ///
    /// `isStillCurrent` is re-checked after the fix resolves. Resolving suspends, and a user switch
    /// in that window clears user-scoped state — without the re-check this task would resume and
    /// rewrite the old user's belief, stamping any resulting event to whoever signed in.
    func evaluateMembership(
        geofenceIds: [String],
        reason: String,
        requiresFreshFix: Bool = false,
        isStillCurrent: (@Sendable () -> Bool)? = nil
    ) async {
        for geofenceId in geofenceIds {
            logger.geofencePolygonEvaluationRequested(identifier: geofenceId, reason: reason)
        }
        // Ids, never rings: one fix serves the batch, and the ring each verdict uses is read after
        // that fix inside `evaluate`, so a refresh landing mid-request cannot be decided against.
        var pending: [String] = []
        for geofenceId in geofenceIds {
            // Builds the ring and discards it, unlike the foreground pass's cheaper `vertices`
            // test: this one runs before the request, so an unbuildable ring is worth catching
            // here rather than spending a whole fix request to reject it after.
            guard let geofence = await cachedGeofence(id: geofenceId), geofence.polygonRegion != nil
            else { continue }
            pending.append(geofenceId)
        }
        guard !pending.isEmpty else { return }
        guard let fix = await resolveFix(requiringFresh: requiresFreshFix) else {
            for geofenceId in pending {
                logger.geofencePolygonUndecided(identifier: geofenceId, reason: "no usable fix")
            }
            return
        }
        for geofenceId in pending {
            await evaluate(geofenceId: geofenceId, fix: fix, isStillCurrent: isStillCurrent)
        }
    }

    /// Re-evaluates every registered polygon when the app comes to the foreground.
    ///
    /// The one case no OS event covers: a device already inside a polygon when monitoring begins
    /// has crossed nothing, so the OS has nothing to report, and a device standing still produces
    /// no movement pass either. Foregrounding is the remaining signal, and it is free — one fix
    /// serves the whole pass.
    ///
    /// Foregrounds arrive in bursts, so a pass already running wins: a second concurrent scan reads
    /// the same storage and the same fix and can only duplicate the location work.
    func evaluateAllPolygons(
        requiresFreshFix: Bool = false,
        isStillCurrent: (@Sendable () -> Bool)? = nil
    ) async {
        guard !isEvaluatingAllPolygons else {
            logger.geofencePolygonPassSkipped(reason: "a pass is already running")
            return
        }
        isEvaluatingAllPolygons = true
        defer { isEvaluatingAllPolygons = false }
        let registered = await storage.getRegisteredBusinessIds()
        let polygons = await storage.getCachedGeofences()
            .filter { registered.contains($0.id) && $0.vertices != nil }
        guard !polygons.isEmpty else { return }
        // One request for the whole pass. Resolving per polygon would issue a fresh timed request
        // for every one of them whenever the cache stays empty, holding the main actor for minutes
        // and still deciding nothing — and a failed fresh request would silently downgrade every
        // polygon after the first to the pre-wake fix.
        guard let fix = await resolveFix(requiringFresh: requiresFreshFix) else {
            for geofence in polygons {
                logger.geofencePolygonUndecided(identifier: geofence.id, reason: "no usable fix")
            }
            return
        }
        for geofence in polygons {
            await evaluate(geofenceId: geofence.id, fix: fix, isStillCurrent: isStillCurrent)
        }
    }

    private func registerForegroundEvaluation() {
        #if canImport(UIKit)
        foregroundObserverToken = notificationCenter.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Sampled here, not read at emit time: the pass resolves a fix first, and a
                // foregrounding app's cached fix is normally stale — the app was suspended — so
                // that request really does suspend. No caller supplies an expected user on this
                // path, so the observer takes its own.
                //
                // Anonymous at both ends compares nil to nil and proceeds; that is safe only
                // because a signed-out process has no `monitoredGeofenceIds`, so the pass returns
                // empty before it resolves anything. Registration while anonymous would break it.
                let expectedUserId = self.contextStore.currentUserId
                Task { [contextStore = self.contextStore] in
                    await self.evaluateAllPolygons(
                        isStillCurrent: { contextStore.currentUserId == expectedUserId }
                    )
                }
            }
        }
        #endif
    }

    private func evaluate(
        geofenceId: String,
        requiresFreshFix: Bool = false,
        isStillCurrent: (@Sendable () -> Bool)? = nil
    ) async {
        guard let fix = await resolveFix(requiringFresh: requiresFreshFix) else {
            logger.geofencePolygonUndecided(identifier: geofenceId, reason: "no usable fix")
            return
        }
        await evaluate(geofenceId: geofenceId, fix: fix, isStillCurrent: isStillCurrent)
    }

    /// Takes an id, never a caller's `PolygonRegion`: resolving a fix suspends, and a refresh can
    /// replace the fence under the same id while it does. A ring captured before the await would
    /// decide against geometry the workspace has already moved off — no user switch required — so
    /// the current one is read here and the stale copy is never in scope to be used by mistake.
    ///
    /// Registration is re-read with it, from the same load: a fence unregistered during the fix
    /// must not be judged either, and sampling one before the await and the other after is how the
    /// two come to disagree. Costs one state decode per polygon, which is the price of the pass's
    /// verdicts being at most one hop stale rather than a whole location request stale — do not
    /// trade it back for a single snapshot without knowing that is what is being traded.
    private func evaluate(
        geofenceId: String,
        fix: CLLocation,
        isStillCurrent: (@Sendable () -> Bool)? = nil
    ) async {
        guard CLLocationCoordinate2DIsValid(fix.coordinate) else {
            logger.geofencePolygonUndecided(identifier: geofenceId, reason: "no usable fix")
            return
        }
        if let isStillCurrent, !isStillCurrent() {
            logger.geofencePolygonUndecided(identifier: geofenceId, reason: "user changed while resolving the fix")
            return
        }
        guard let geofence = await storage.getRegisteredGeofence(id: geofenceId),
              let polygon = geofence.polygonRegion
        else {
            logger.geofencePolygonUndecided(identifier: geofenceId, reason: "no longer a registered polygon")
            return
        }
        let point = LocationData(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude)
        let signedEdgeDistance = polygon.signedEdgeDistance(to: point)
        guard let membership = PolygonMembershipDecision.resolvedMembership(
            signedEdgeDistance: signedEdgeDistance,
            horizontalAccuracy: fix.horizontalAccuracy,
            fixAge: -fix.timestamp.timeIntervalSinceNow
        ) else {
            logger.geofencePolygonUndecided(
                identifier: geofence.id,
                reason: "edge distance \(Int(signedEdgeDistance)) m within accuracy \(Int(fix.horizontalAccuracy)) m"
            )
            return
        }
        logger.geofencePolygonVerdict(
            identifier: geofence.id, membership: membership,
            signedEdgeDistance: signedEdgeDistance, horizontalAccuracy: fix.horizontalAccuracy,
            fixAge: -fix.timestamp.timeIntervalSinceNow
        )
        await apply(
            membership, to: geofence, evidence: fix.timestamp,
            confirmedByFix: true, evaluatedRing: geofence.vertices, isStillCurrent: isStillCurrent
        )
    }

    /// Applies a membership verdict and delivers the crossing when it changes the stored belief.
    /// `evidence` is when the crossing happened — a fix's timestamp, or the OS event's date for a
    /// covering-circle exit. Required, not optional: it is what orders the write against the stored
    /// belief, and a caller allowed to omit it could silently write an unordered one. `confirmedByFix`
    /// says which of the two it was, since both carry a date and the date alone cannot tell the log
    /// how membership was decided.
    ///
    /// `isStillCurrent` is re-checked here, immediately before the emit and with no await after it:
    /// the tracker stamps whoever is current when it is entered, and the write below is an await of
    /// its own. The write is left unguarded deliberately — a belief states geometry, true whoever
    /// is signed in; an emit is an ATTRIBUTION, and attribution is what a switch invalidates.
    ///
    /// `evaluatedRing` is the geometry the verdict was computed from, and the write is refused if
    /// the workspace has moved off it since. Nil from the covering-circle exit, and that is not an
    /// omission: polygon ⊆ circle holds for whatever ring is current, so leaving the circle is a
    /// verdict no replacement can invalidate. Only a ring-derived verdict can go stale with the ring.
    private func apply(
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
        guard case .deliver(let transition) = outcome,
              geofence.transitionTypes.contains(transition)
        else {
            logger.geofencePolygonNotDelivered(identifier: geofence.id, outcome: "\(outcome)")
            return
        }
        if let isStillCurrent, !isStillCurrent() {
            logger.geofencePolygonNotDelivered(identifier: geofence.id, outcome: "user changed before delivery")
            return
        }
        logger.geofencePolygonTransition(
            identifier: geofence.id,
            transition: transition,
            confirmedByFix: confirmedByFix
        )
        await transitionEmitter.trackTransition(geofenceId: geofence.id, transition: transition)
    }

    private func cachedGeofence(id: String) async -> Geofence? {
        await storage.getCachedGeofences().first { $0.id == id }
    }

    /// Freshest fix obtainable, requesting one when the cache is stale. Mirrors the gate's
    /// resolution: the completion's coordinates are discarded in favour of `latestFix`, which
    /// carries the accuracy and timestamp the decision needs.
    ///
    /// When a fresh fix is REQUIRED, a request that fails or times out still resumes with the fix
    /// already held. That one predates the wake and can sit inside `movementFixMaxAge`, so it would
    /// re-affirm the very verdict the wake exists to revisit — report no fix instead.
    private func resolveFix(requiringFresh: Bool = false) async -> CLLocation? {
        let priorTimestamp = fixResolver.latestFix?.timestamp
        return await withCheckedContinuation { continuation in
            fixResolver.resolve(cached: requiringFresh ? nil : fixResolver.cachedFix) { [weak self] _ in
                guard let self else { return continuation.resume(returning: nil) }
                let resolved = fixResolver.latestFix
                if requiringFresh, let resolved, let priorTimestamp, resolved.timestamp <= priorTimestamp {
                    continuation.resume(returning: nil)
                    return
                }
                // Cold process: nothing delivered and the request failed, so CoreLocation's own
                // cached fix is the only evidence there is. The monitor has already advanced its
                // dedup baseline, so declining here loses the crossing for good.
                continuation.resume(returning: resolved ?? fixResolver.cachedFix)
            }
        }
    }
}
