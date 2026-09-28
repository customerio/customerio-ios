import CioInternalCommon
import CoreLocation
import Foundation

/// Receipt, buffering and dispatch of classic region events. Members are `internal` only because
/// they live in a separate file from the state they use.
@MainActor
extension CoreLocationGeofenceMonitor {
    struct PendingRegionEvent {
        let identifier: String
        let transition: GeofenceTransition
        let location: LocationData?
        /// Region callbacks carry no date, so this is receipt time; a drain minutes later must not
        /// read as happening now.
        let receivedAt: Date
        /// Captured at intake: by drain time the region may have been replaced under the same id.
        let circle: MonitoredCircle
        /// Fix at receipt, so the deferred `os.callback.received` record reports receive-time truth.
        let fix: CLLocation?
        let fixSource: GeofenceLog.FixSource
    }

    /// Delivers a region event, holding it until the bootstrap binds `onTransition`: on a cold wake
    /// the delegate can go live before bind/adopt run, and the OS never re-emits a dropped crossing.
    /// Ownership is checked at drain, after adopt populated it, which still filters host-app events.
    /// New arrivals queue behind any backlog or in-flight drain, so per-region order holds. The cap
    /// only bites if bind never runs, and then every buffered event is undeliverable anyway.
    func handleRegionEvent(_ region: CLRegion, transition: GeofenceTransition) {
        guard let circular = region as? CLCircularRegion else { return }
        let circle = MonitoredCircle(
            center: LocationData(latitude: circular.center.latitude, longitude: circular.center.longitude),
            radius: circular.radius,
            maximumRadius: manager.maximumRegionMonitoringDistance
        )
        let mustBuffer = onTransition == nil || !pendingEvents.isEmpty || isDrainingPendingEvents
        // The fix is read at receipt, but the record is only emitted once the region is known to be
        // ours: the host app's own regions reach this delegate too, and their identifiers must not
        // land in our diagnostics.
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
            buffered: false,
            now: dateUtil.now
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
                // Emitted at drain, where ownership is first knowable on a cold wake; `buf=true`
                // marks the delay.
                self.logger.geofenceCallbackReceived(
                    identifier: next.identifier,
                    transition: next.transition,
                    fix: next.fix,
                    source: next.fixSource,
                    buffered: true,
                    now: self.dateUtil.now
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
        // Read off the `CLCircularRegion` the OS hands over, so always known outright.
        circle: MonitoredCircle
    ) {
        if identifier == GeofenceConstants.movementTriggerIdentifier, transition == .exit {
            movementFixResolver.resolve(cached: bestKnownFix(), purpose: .pendingEvents) { [weak self] location, isFresh in
                self?.logger.geofenceCallbackDispatched(identifier: identifier, transition: transition)
                // Falling back to the captured location is a second layer of staleness on top of a
                // failed request, so it can never be reported as current.
                self?.onTransition?(
                    identifier, transition, location ?? capturedLocation, occurredAt,
                    isFresh && location != nil, .circle(circle)
                )
            }
            return
        }
        logger.geofenceCallbackDispatched(identifier: identifier, transition: transition)
        onTransition?(identifier, transition, capturedLocation, occurredAt, false, .circle(circle))
    }
}
