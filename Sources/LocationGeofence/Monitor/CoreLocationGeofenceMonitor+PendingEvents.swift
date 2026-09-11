import CioInternalCommon
import CoreLocation
import Foundation

/// Receipt, buffering and dispatch of classic region events, split out to keep the monitor's
/// registration and lifecycle plumbing readable (same convention as `CLMonitorGeofenceMonitor+*`).
/// Members are `internal` (not `private`) only because they live in a separate file from the
/// stored state they use; they remain monitor implementation detail.
@MainActor
extension CoreLocationGeofenceMonitor {
    struct PendingRegionEvent {
        let identifier: String
        let transition: GeofenceTransition
        let location: LocationData?
        /// CoreLocation's region callbacks carry no date, so this is when we received it — which is
        /// what a queued event needs so a drain minutes later is not read as happening now.
        let receivedAt: Date
        /// The circle the OS raised this against, captured at intake — by drain time the region may
        /// have been replaced under the same identifier.
        let circle: MonitoredCircle
        /// Fix as it stood when the OS reported the crossing. Carried so the deferred
        /// `os.callback.received` record reports receive-time truth rather than drain-time.
        let fix: CLLocation?
        let fixSource: GeofenceLog.FixSource
    }

    /// Delivers a region event, holding it until the bootstrap binds `onTransition`: on a cold wake
    /// the delegate can go live before bind/adopt run (any DI path constructing the monitor), and a
    /// crossing delivered then would be dropped with no re-emission. Ownership is checked at drain —
    /// after adopt populated it — which still filters buffered host-app events. New arrivals queue
    /// behind any backlog and behind an in-flight drain, so per-region order holds. Capped against a
    /// process that never binds; unlike CLMonitor there is no re-emission, but overflowing the cap
    /// requires bind to never run, and then every buffered event is undeliverable anyway.
    func handleRegionEvent(_ region: CLRegion, transition: GeofenceTransition) {
        guard let circular = region as? CLCircularRegion else { return }
        let circle = MonitoredCircle(
            center: LocationData(latitude: circular.center.latitude, longitude: circular.center.longitude),
            radius: circular.radius,
            maximumRadius: manager.maximumRegionMonitoringDistance
        )
        let mustBuffer = onTransition == nil || !pendingEvents.isEmpty || isDrainingPendingEvents
        // The classic delegate carries no event date, so unlike the CLMonitor path there is no way
        // to tell how long the OS sat on this before handing it over. `buf` at least distinguishes
        // a crossing that waited on our own side for a handler to be bound.
        //
        // The fix is read here, when the OS handed the crossing over, but the record is only
        // emitted once the region is known to be ours. A host app's own circular regions reach
        // this delegate too, and recording before the ownership check wrote crossings we never
        // owned — and the host's region identifiers — into a capture we hand around.
        let receivedFix = bestKnownFixDetail()
        if mustBuffer {
            pendingEvents.append(PendingRegionEvent(
                identifier: region.identifier,
                transition: transition,
                location: currentLocationData(),
                receivedAt: Date(),
                circle: circle,
                fix: receivedFix?.fix,
                fixSource: receivedFix?.source ?? .none
            ))
            if pendingEvents.count > Self.maxPendingEvents { pendingEvents.removeFirst() }
            drainPendingEventsIfReady()
            return
        }
        guard ownedRegionIdentifiers.contains(region.identifier) else { return }
        logger.geofenceCallbackReceived(
            identifier: region.identifier,
            transition: transition,
            fix: receivedFix?.fix,
            source: receivedFix?.source ?? .none,
            buffered: false
        )
        dispatchTransition(
            identifier: region.identifier, transition: transition,
            capturedLocation: currentLocationData(), occurredAt: Date(), circle: circle
        )
    }

    func drainPendingEventsIfReady() {
        guard onTransition != nil, !isDrainingPendingEvents, !pendingEvents.isEmpty else { return }
        isDrainingPendingEvents = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            while self.onTransition != nil, !self.pendingEvents.isEmpty {
                let next = self.pendingEvents.removeFirst()
                guard self.ownedRegionIdentifiers.contains(next.identifier) else { continue }
                // Emitted at drain, not at receive: on the cold-wake path ownership is only
                // knowable here. `buf=true` marks that delay; the fix is the one read when the OS
                // reported the crossing, not the one current at drain.
                self.logger.geofenceCallbackReceived(
                    identifier: next.identifier,
                    transition: next.transition,
                    fix: next.fix,
                    source: next.fixSource,
                    buffered: true
                )
                self.dispatchTransition(
                    identifier: next.identifier, transition: next.transition,
                    capturedLocation: next.location, occurredAt: next.receivedAt, circle: next.circle
                )
            }
            self.isDrainingPendingEvents = false
        }
    }

    /// Movement-trigger EXITs re-center the trigger and measure displacement at the attached
    /// coords, so a frozen cached fix pins the whole pipeline to a stale point — freshen it first,
    /// keeping the captured location only as the fallback. Fire-and-forget so a slow fix can't
    /// stall the pending-event drain behind it. Business events keep the captured location.
    func dispatchTransition(
        identifier: String,
        transition: GeofenceTransition,
        capturedLocation: LocationData?,
        occurredAt: Date,
        // The classic path reads the circle off the `CLCircularRegion` the OS hands it, so it is
        // always known outright — there is no generation to look up and nothing to expire.
        circle: MonitoredCircle
    ) {
        if identifier == GeofenceConstants.movementTriggerIdentifier, transition == .exit {
            movementFixResolver.resolve(cached: bestKnownFix(), purpose: .pendingEvents) { [weak self] location, isFresh in
                self?.logger.geofenceOsTransitionReceived(identifier: identifier, transition: transition)
                // Falling back to the captured location is a second layer of staleness on top of a
                // failed request, so it can never be reported as current.
                self?.onTransition?(
                    identifier, transition, location ?? capturedLocation, occurredAt,
                    isFresh && location != nil, .circle(circle)
                )
            }
            return
        }
        logger.geofenceOsTransitionReceived(identifier: identifier, transition: transition)
        onTransition?(identifier, transition, capturedLocation, occurredAt, false, .circle(circle))
    }
}
