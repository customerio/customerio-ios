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
    private var foregroundObserverToken: NSObjectProtocol?
    private var isEvaluatingAllPolygons = false

    init(
        storage: GeofenceStorage,
        transitionEmitter: GeofenceTransitionEmitting,
        logger: Logger,
        fixResolver: MovementFixResolver? = nil
    ) {
        self.storage = storage
        self.transitionEmitter = transitionEmitter
        self.logger = logger
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
    func handleTransition(identifier: String, transition: GeofenceTransition, occurredAt: Date) async {
        guard let geofence = await cachedGeofence(id: identifier), geofence.vertices != nil else {
            // Uncached, or a genuine circle: forward untouched, the behaviour that predates polygons.
            await transitionEmitter.trackTransition(geofenceId: identifier, transition: transition)
            return
        }
        switch transition {
        case .exit:
            // polygon ⊆ covering circle, so leaving the circle is geometric certainty: it needs no
            // fix, and no ring either — which is why this runs before the geometry is built. It is
            // still ORDERED against the stored belief: a synthesized or replayed exit arriving
            // after a newer enter would otherwise swallow it and leave the device believed outside
            // while it sits inside.
            await apply(.outside, to: geofence, evidence: occurredAt, confirmedByFix: false)
        case .enter:
            guard let polygon = geofence.polygonRegion else {
                // A stored ring that no longer builds is NOT a circle — forwarding it would fire a
                // customer enter anywhere inside the covering circle.
                logger.geofencePolygonUndecided(identifier: identifier, reason: "stored ring no longer builds")
                return
            }
            await evaluate(geofence: geofence, polygon: polygon)
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
    func evaluateAllPolygons() async {
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
        // and still deciding nothing.
        guard let fix = await resolveFix() else {
            for geofence in polygons {
                logger.geofencePolygonUndecided(identifier: geofence.id, reason: "no usable fix")
            }
            return
        }
        for geofence in polygons {
            guard let polygon = geofence.polygonRegion else { continue }
            await evaluate(geofence: geofence, polygon: polygon, fix: fix)
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

    private func evaluate(geofence: Geofence, polygon: PolygonRegion) async {
        guard let fix = await resolveFix() else {
            logger.geofencePolygonUndecided(identifier: geofence.id, reason: "no usable fix")
            return
        }
        await evaluate(geofence: geofence, polygon: polygon, fix: fix)
    }

    private func evaluate(geofence: Geofence, polygon: PolygonRegion, fix: CLLocation) async {
        guard CLLocationCoordinate2DIsValid(fix.coordinate) else {
            logger.geofencePolygonUndecided(identifier: geofence.id, reason: "no usable fix")
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
        await apply(membership, to: geofence, evidence: fix.timestamp, confirmedByFix: true)
    }

    /// Applies a membership verdict and delivers the crossing when it changes the stored belief.
    /// `evidence` is when the crossing happened — a fix's timestamp, or the OS event's date for a
    /// covering-circle exit. Required, not optional: it is what orders the write against the stored
    /// belief, and a caller allowed to omit it could silently write an unordered one. `confirmedByFix`
    /// says which of the two it was, since both carry a date and the date alone cannot tell the log
    /// how membership was decided.
    private func apply(
        _ membership: PolygonMembership,
        to geofence: Geofence,
        evidence: Date,
        confirmedByFix: Bool
    ) async {
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
    private func resolveFix() async -> CLLocation? {
        await withCheckedContinuation { continuation in
            fixResolver.resolve(cached: fixResolver.cachedFix) { [weak self] _ in
                // `cachedFix` again on failure: on a cold process this resolver has delivered
                // nothing, and the monitor has already advanced its dedup baseline, so declining
                // here loses the crossing for good. The decision's age gate bounds how stale it can be.
                continuation.resume(returning: self?.fixResolver.cachedFix)
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
        logger: DIGraphShared.shared.logger
    )
}
