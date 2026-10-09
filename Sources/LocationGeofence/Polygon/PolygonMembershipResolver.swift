import CioInternalCommon
import CoreLocation
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Turns OS covering-circle events into polygon transitions. An ENTER needs a gated fix inside the
/// polygon; an EXIT needs a covering-circle exit or a gated fix outside.
@MainActor
final class PolygonMembershipResolver {
    let storage: GeofenceStorage
    let fixResolver: MovementFixResolver
    let transitionEmitter: GeofenceTransitionEmitting
    let dwellCoordinator: GeofenceDwellCoordinator?
    let logger: Logger
    let contextStore: BackgroundDeliveryContextStore
    let dateUtil: DateUtil
    let notificationCenter: NotificationCenter
    var foregroundObserverToken: NSObjectProtocol?

    private var passesInFlight = 0
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
        notificationCenter: NotificationCenter = .default,
        dwellCoordinator: GeofenceDwellCoordinator? = nil
    ) {
        self.storage = storage
        self.transitionEmitter = transitionEmitter
        self.logger = logger
        self.contextStore = contextStore
        self.dateUtil = dateUtil
        self.notificationCenter = notificationCenter
        self.dwellCoordinator = dwellCoordinator
        // Ten metres, not the circle path's 100: a 100 m fix can't decide a minimum-size polygon.
        self.fixResolver = fixResolver ?? MovementFixResolver(
            logger: logger,
            backgroundTaskRunner: GeofenceBackgroundTime.runner(name: "io.customer.geofence.polygon-fix"),
            dateUtil: dateUtil,
            desiredAccuracy: kCLLocationAccuracyNearestTenMeters
        )
        registerForegroundEvaluation()
        dwellCoordinator?.polygonVerifier = { [weak self] geofenceId in
            guard let self else { return }
            _ = await self.evaluateMembership(
                geofenceIds: [geofenceId], reason: .foreground, requiresFreshFix: true
            )
        }
    }

    deinit {
        if let foregroundObserverToken {
            notificationCenter.removeObserver(foregroundObserverToken)
        }
    }

    /// A geofence missing from the cache is forwarded as a circle: losing a real crossing is worse
    /// than reporting a covering-circle-shaped one. It carries no visit, having no fence to measure.
    /// - Parameter receivedForUserId: who was identified when the OS delivered the callback, read
    ///   synchronously in it; `""` when anonymous. Nil reads it on entry instead.
    /// - Parameter entryObserved: whether a circle fence's ENTER may start an observed visit; see
    ///   `GeofenceTransitionHandler`.
    @discardableResult
    func handleTransition(
        identifier: String,
        transition: GeofenceTransition,
        occurredAt: Date,
        eventCircle: GeofenceEventCircle = .unknown,
        receivedForUserId: String? = nil,
        entryObserved: Bool = true
    ) async -> PolygonTransitionOutcome {
        // A switch during the awaits below must not relabel this crossing or its visit. Anonymous
        // maps to "" so no later sign-in can claim it either.
        let receivedForUserId = receivedForUserId ?? contextStore.currentUserId ?? ""
        // One read for both answers, so an uncached ENTER meets its user check after exactly the
        // storage round trip it always had.
        let geofence: Geofence
        switch await storage.transitionTarget(id: identifier) {
        case .cached(let cached):
            geofence = cached
        case .uncached(let unconfigured):
            await forwardUncachedTransition(
                identifier: identifier, transition: transition, occurredAt: occurredAt,
                receivedForUserId: receivedForUserId, unconfigured: unconfigured
            )
            return .nothingToRearm
        }
        guard geofence.vertices != nil else {
            await forwardCircleTransition(
                geofence: geofence, transition: transition, occurredAt: occurredAt,
                receivedForUserId: receivedForUserId, entryObserved: entryObserved,
                raisedByCurrentCircle: Self.circle(eventCircle, raisedEventsOf: geofence)
            )
            return .nothingToRearm
        }
        switch transition {
        case .dwell:
            // Core Location never produces dwell transitions. Dwell is emitted only after this
            // resolver supplies fresh, real-shape membership evidence to the dwell coordinator.
            return .nothingToRearm
        case .exit:
            await applyCoveringCircleExit(
                geofence: geofence, eventCircle: eventCircle, occurredAt: occurredAt,
                receivedForUserId: receivedForUserId
            )
            return .nothingToRearm
        case .enter:
            guard geofence.polygonRegion != nil else {
                // Not a circle: forwarding would fire an enter anywhere inside the covering circle.
                logger.geofencePolygonUndecided(identifier: identifier, reason: .ringUnbuildable, pass: nil)
                return .nothingToRearm
            }
            // No user-switch guard: the dedup baseline has already advanced, so declining loses the
            // crossing for good.
            guard let fix = await evaluate(geofenceId: identifier, requiresFreshFix: true) else {
                return .nothingToRearm
            }
            return .circleEntered(fix: ResolvedFix(fix))
        }
    }

    /// - Returns: whether a usable fix was obtained (true when there was nothing to evaluate).
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
        // Ids, never rings: each ring is re-read after the fix, so a stale one is never judged.
        var pending: [String] = []
        for geofenceId in geofenceIds {
            // Builds the ring, so an unbuildable one is dropped before a fix request is spent.
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

    /// A pass already in flight wins unless this one requires a fresh fix: a wake runs because the
    /// device moved, so it never yields.
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
        // Before the empty guard: `n=0` records that a pass ran with nothing to judge.
        let pass = nextPass()
        let heldFixDecision = heldFixUse(heldFix)
        logger.geofencePolygonPassStarted(reason: reason, count: polygons.count, pass: pass, heldFix: heldFixDecision.use)
        guard polygons.isEmpty == false else {
            // A circle-only pass needs no new location request, but a fresh fix already held
            // by the caller can still prove an existing circle visit ended.
            guard heldFixDecision.age >= 0 else { return }
            let location: CLLocation?
            switch heldFixDecision.use {
            case .reused: location = heldFix?.location
            case .newer: location = heldFixDecision.newerFix
            case .none, .tooOld: location = nil
            }
            if let location {
                await dwellCoordinator?.recordOutsideEvidence(fix: location, expectedUserId: nil)
            }
            return
        }
        // One request per pass: per-polygon requests would each hold the main actor for a timeout.
        guard let fix = await passFix(heldFix: heldFix, decision: heldFixDecision, requiringFresh: requiresFreshFix) else {
            for geofence in polygons {
                logger.geofencePolygonUndecided(identifier: geofence.id, reason: .noUsableFix, pass: pass)
            }
            return
        }
        await runPass(geofenceIds: polygons.map(\.id), fix: fix, pass: pass, isStillCurrent: isStillCurrent)
    }

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

    /// Takes an id, never a region: a refresh can replace the fence during the fix, so the ring and
    /// registration are re-read here.
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

    private func cachedGeofence(id: String) async -> Geofence? {
        await storage.getCachedGeofences().first { $0.id == id }
    }
}
