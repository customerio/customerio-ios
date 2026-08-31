import CioInternalCommon
import CoreLocation
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Turns OS covering-circle events and tripwire wakes into customer-facing polygon transitions.
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
    private let coordinator: GeofenceSyncCoordinator
    private let fixResolver: MovementFixResolver
    private let logger: Logger
    private var foregroundObserverToken: NSObjectProtocol?

    init(
        storage: GeofenceStorage,
        transitionEmitter: GeofenceTransitionEmitting,
        coordinator: GeofenceSyncCoordinator,
        logger: Logger,
        fixResolver: MovementFixResolver? = nil
    ) {
        self.storage = storage
        self.transitionEmitter = transitionEmitter
        self.coordinator = coordinator
        self.logger = logger
        self.fixResolver = fixResolver ?? MovementFixResolver(
            logger: logger,
            backgroundTaskRunner: GeofenceBackgroundTime.runner(name: "io.customer.geofence.polygon-fix")
        )
        registerForegroundEvaluation()
    }

    deinit {
        if let foregroundObserverToken {
            NotificationCenter.default.removeObserver(foregroundObserverToken)
        }
    }

    /// Routes a business-geofence transition the OS delivered. A circle fence is forwarded to the
    /// tracker unchanged; a polygon's covering-circle event is interpreted against membership.
    ///
    /// A geofence missing from the cache (a sync raced this event, or the OS still holds a
    /// condition the cache has dropped) is forwarded rather than dropped: treating it as a circle
    /// is the behaviour that predates polygons, and losing a real crossing is worse than a
    /// covering-circle-shaped one.
    func handleTransition(identifier: String, transition: GeofenceTransition, location: LocationData?) async {
        logger.geofenceOsTransitionReceived(identifier: identifier, transition: transition)
        guard let geofence = await cachedGeofence(id: identifier),
              let polygon = geofence.polygonRegion
        else {
            await transitionEmitter.trackTransition(geofenceId: identifier, transition: transition)
            return
        }
        switch transition {
        case .exit:
            // polygon ⊆ covering circle, so leaving the circle is geometric certainty and needs no
            // fix. The tripwire goes with it: outside the circle there is no annulus to watch.
            await apply(.outside, to: geofence, evidence: nil)
            await clearTripwire(for: geofence.id, at: location)
        case .enter:
            await evaluate(geofence: geofence, polygon: polygon, containment: .coveringCircleEnter)
        }
    }

    /// Re-evaluates membership for one polygon: the wake path used by tripwire exits, and the
    /// entry point for a polygon that has just been registered, where the device may already be
    /// standing inside and no crossing will ever be delivered. A geofence that is no longer cached
    /// or no longer a polygon has nothing to decide.
    ///
    /// Logged because this path bypasses `handleTransition`, so nothing else records that we were
    /// asked to re-check. Reading the absence of a log line as an absence of evaluations led to
    /// exactly the wrong conclusion once already.
    /// `requiresFreshFix` is set by the tripwire wake, which fires *because* the device moved far
    /// enough to change the verdict. Answering it from the cached fix — the one that planted the
    /// tripwire, still inside `movementFixMaxAge` — replays the same verdict, leaves the tripwire
    /// unchanged so nothing is re-planted, and consumes the wake for nothing. Measured on a 30 m/s
    /// simulated drive: a 15 s-old fix is 450 m stale, and the polygon's ENTER was never delivered.
    func evaluateMembership(geofenceId: String, reason: String, requiresFreshFix: Bool = false) async {
        logger.geofencePolygonEvaluationRequested(identifier: geofenceId, reason: reason)
        guard let geofence = await cachedGeofence(id: geofenceId),
              let polygon = geofence.polygonRegion
        else { return }
        await evaluate(geofence: geofence, polygon: polygon, requiresFreshFix: requiresFreshFix)
    }

    /// Re-evaluates every registered polygon when the app comes to the foreground.
    ///
    /// The one case no OS event covers: a device already inside a polygon when monitoring begins
    /// has crossed nothing, so the OS has nothing to report, and a device standing still produces
    /// no movement pass either. Foregrounding is the remaining signal, and it is free — the first
    /// evaluation resolves a fix and the rest read it from the cache.
    func evaluateAllPolygons() async {
        let registered = await storage.getRegisteredBusinessIds()
        let polygons = await storage.getCachedGeofences()
            .filter { registered.contains($0.id) && $0.vertices != nil }
        for geofence in polygons {
            guard let polygon = geofence.polygonRegion else { continue }
            await evaluate(geofence: geofence, polygon: polygon)
        }
    }

    private func registerForegroundEvaluation() {
        #if canImport(UIKit)
        foregroundObserverToken = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.evaluateAllPolygons() }
            }
        }
        #endif
    }

    /// How we know whether the device is inside the covering circle, which decides whether a
    /// tripwire is worth a slot. The distinction matters because our own fix can be staler than the
    /// event we are reacting to.
    private enum ContainmentEvidence {
        /// The OS reported a crossing INTO the covering circle. That is stronger than any fix we
        /// hold: it is the OS's own evaluation, at the moment it happened.
        case coveringCircleEnter
        /// No OS statement — containment has to be inferred from the fix.
        case fixOnly
    }

    private func evaluate(
        geofence: Geofence,
        polygon: PolygonRegion,
        containment: ContainmentEvidence = .fixOnly,
        requiresFreshFix: Bool = false
    ) async {
        guard let fix = await resolveFix(requiringFresh: requiresFreshFix),
              CLLocationCoordinate2DIsValid(fix.coordinate)
        else {
            logger.geofencePolygonUndecided(identifier: geofence.id, reason: "no usable fix")
            return
        }
        let point = LocationData(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude)
        let signedEdgeDistance = polygon.signedEdgeDistance(to: point)
        // A tripwire is only worth a slot inside the covering circle. Outside it the OS's own
        // covering-circle enter is the wake, and a tripwire would be a region that can never fire
        // first — this path is reached for EVERY registered polygon on a foreground evaluation,
        // including ones the device is kilometres from, so planting unconditionally burns the
        // scarce 20-region budget on wakes that cannot happen.
        //
        // Planted before the verdict is consulted, and whatever the verdict is: an undecided
        // evaluation still needs a wake to try again from, and that is exactly the annulus case the
        // tripwire exists for.
        let headroom = geofence.radius - geofence.distanceTo(point)
        switch containment {
        case .coveringCircleEnter:
            // The OS just said we are inside, so never clear here, whatever our fix says. Measured
            // in the field: a 15.5 s-old cached fix — well within `movementFixMaxAge` — placed the
            // device ~400 m from where it was, outside a circle it had just entered, and retired
            // the tripwire for the whole 12 minutes it then spent in the annulus.
            await updateTripwire(for: geofence.id, center: point, signedEdgeDistance: signedEdgeDistance)
        case .fixOnly:
            if headroom > 0 {
                await updateTripwire(for: geofence.id, center: point, signedEdgeDistance: signedEdgeDistance)
            } else if -headroom > max(fix.horizontalAccuracy, GeofenceConstants.baselineHealMinEdgeMargin) {
                // Retire it only when decisively outside. Inside the uncertainty band, leaving the
                // tripwire alone costs a slot; dropping it can cost a crossing.
                await clearTripwire(for: geofence.id, at: point)
            }
        }
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
        await apply(membership, to: geofence, evidence: fix.timestamp)
    }

    /// Applies a membership verdict and delivers the crossing when it changes the stored belief.
    /// `evidence` is the fix's timestamp, or `nil` for the covering-circle exit, which is
    /// geometric rather than fix-derived and so is never outranked by a newer belief.
    private func apply(_ membership: PolygonMembership, to geofence: Geofence, evidence: Date?) async {
        let outcome = await storage.recordPolygonMembership(
            membership,
            forIdentifier: geofence.id,
            onlyIfBeliefPredates: evidence
        )
        guard case .deliver(let transition) = outcome,
              geofence.transitionTypes.contains(transition)
        else { return }
        logger.geofencePolygonTransition(
            identifier: geofence.id,
            transition: transition,
            confirmedByFix: evidence != nil
        )
        await transitionEmitter.trackTransition(geofenceId: geofence.id, transition: transition)
    }

    /// Plants or moves the tripwire so it sits on the device with a radius reaching the polygon
    /// boundary — leaving it is precisely the point at which this evaluation's verdict stops being
    /// safe to trust. Floored, because below that the OS promotes crossings too unreliably.
    ///
    /// Deliberately NOT capped at the distance left inside the covering circle. Capping sounds
    /// tidy — it keeps the tripwire a strictly earlier signal than the circle's own exit — but a
    /// tripwire larger than the circle is merely redundant, while a small one is not promoted at
    /// all, and the cap pinned the radius to the floor at exactly the moment a covering-circle
    /// enter plants one. Promotability wins over tidiness.
    ///
    /// Persisted before the re-registration so a sync racing this call still composes it into the
    /// desired set. An unchanged tripwire is left alone: re-registering the same circle would risk
    /// absorbing a crossing the OS has detected but not yet delivered.
    private func updateTripwire(for geofenceId: String, center: LocationData, signedEdgeDistance: Double) async {
        let tripwire = PolygonTripwire(
            center: center,
            radius: max(abs(signedEdgeDistance), GeofenceConstants.polygonTripwireMinRadius)
        )
        guard await storage.getPolygonTripwires()[geofenceId] != tripwire else { return }
        await storage.setPolygonTripwire(tripwire, forIdentifier: geofenceId)
        logger.geofencePolygonTripwirePlanted(identifier: geofenceId, radius: tripwire.radius)
        _ = await coordinator.reapplyRegistration(latitude: center.latitude, longitude: center.longitude)
    }

    /// Drops the tripwire once its polygon's covering circle has been left. Without a location the
    /// re-registration is skipped rather than guessed at — the tripwire is already gone from
    /// storage, so the next sync composes a desired set without it and the OS condition goes then.
    private func clearTripwire(for geofenceId: String, at location: LocationData?) async {
        guard await storage.clearPolygonTripwire(forIdentifier: geofenceId) else { return }
        logger.geofencePolygonTripwireCleared(identifier: geofenceId)
        guard let location else { return }
        _ = await coordinator.reapplyRegistration(latitude: location.latitude, longitude: location.longitude)
    }

    private func cachedGeofence(id: String) async -> Geofence? {
        await storage.getCachedGeofences().first { $0.id == id }
    }

    /// Freshest fix obtainable, requesting one when the cache is stale. Mirrors the gate's
    /// resolution: the completion's coordinates are discarded in favour of `latestFix`, which
    /// carries the accuracy and timestamp the decision needs.
    private func resolveFix(requiringFresh: Bool = false) async -> CLLocation? {
        await withCheckedContinuation { continuation in
            fixResolver.resolve(cached: requiringFresh ? nil : fixResolver.latestFix) { [weak self] _ in
                continuation.resume(returning: self?.fixResolver.latestFix)
            }
        }
    }
}

// MARK: - DI

extension DIGraphShared {
    /// Hand-written + `@MainActor`-isolated for the same reason as `geofenceMonitor`: the resolver
    /// owns a `MovementFixResolver`, which owns a `CLLocationManager`. Override-check mirrors the
    /// generated accessors so tests can substitute via `di.override(value:forType:)`.
    @MainActor
    var polygonMembershipResolver: PolygonMembershipResolver {
        let overridden: PolygonMembershipResolver? = getOverriddenInstance()
        return overridden ?? PolygonMembershipResolver.shared
    }
}

extension PolygonMembershipResolver {
    /// Process-wide singleton so one `CLLocationManager` serves every evaluation; the resolver
    /// itself is stateless, all belief lives in `GeofenceStorage`.
    @MainActor
    static let shared = PolygonMembershipResolver(
        storage: DIGraphShared.shared.geofenceStorage,
        transitionEmitter: DIGraphShared.shared.geofenceEventTracker,
        coordinator: DIGraphShared.shared.geofenceSyncCoordinator,
        logger: DIGraphShared.shared.logger
    )
}
