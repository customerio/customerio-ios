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

    init(
        storage: GeofenceStorage,
        transitionEmitter: GeofenceTransitionEmitting,
        logger: Logger,
        fixResolver: MovementFixResolver? = nil
    ) {
        self.storage = storage
        self.transitionEmitter = transitionEmitter
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
    func handleTransition(identifier: String, transition: GeofenceTransition) async {
        logger.geofenceOsTransitionReceived(identifier: identifier, transition: transition)
        guard let geofence = await cachedGeofence(id: identifier),
              let polygon = geofence.polygonRegion
        else {
            await transitionEmitter.trackTransition(geofenceId: identifier, transition: transition)
            return
        }
        switch transition {
        case .exit:
            // polygon ⊆ covering circle, so leaving the circle is geometric certainty and needs
            // no fix.
            await apply(.outside, to: geofence, evidence: nil)
        case .enter:
            await evaluate(geofence: geofence, polygon: polygon)
        }
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

    private func evaluate(geofence: Geofence, polygon: PolygonRegion) async {
        guard let fix = await resolveFix(), CLLocationCoordinate2DIsValid(fix.coordinate) else {
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

    private func cachedGeofence(id: String) async -> Geofence? {
        await storage.getCachedGeofences().first { $0.id == id }
    }

    /// Freshest fix obtainable, requesting one when the cache is stale. Mirrors the gate's
    /// resolution: the completion's coordinates are discarded in favour of `latestFix`, which
    /// carries the accuracy and timestamp the decision needs.
    private func resolveFix() async -> CLLocation? {
        await withCheckedContinuation { continuation in
            fixResolver.resolve(cached: fixResolver.latestFix) { [weak self] _ in
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
        logger: DIGraphShared.shared.logger
    )
}
