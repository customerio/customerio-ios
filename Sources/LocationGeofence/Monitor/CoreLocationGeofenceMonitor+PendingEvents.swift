import CioInternalCommon
import CoreLocation
import Foundation

@MainActor
extension CoreLocationGeofenceMonitor {
    struct PendingRegionEvent {
        let identifier: String
        let transition: GeofenceTransition
        let location: LocationData?
        /// Callbacks carry no date, so a drain minutes later must not read as happening now.
        let receivedAt: Date
        /// Captured at intake: by drain time the region may have been replaced under the same id.
        let circle: MonitoredCircle
        /// Fix at receipt, so the deferred `os.callback.received` reports receive-time truth.
        let fix: CLLocation?
        let fixSource: GeofenceLog.FixSource
    }

    /// Held until `onTransition` is bound: on a cold wake the delegate can go live first, and the OS
    /// never re-emits a dropped crossing. Ownership is checked at drain, once adopt has populated it.
    func handleRegionEvent(_ region: CLRegion, transition: GeofenceTransition) {
        guard let circular = region as? CLCircularRegion else { return }
        let circle = MonitoredCircle(
            center: LocationData(latitude: circular.center.latitude, longitude: circular.center.longitude),
            radius: circular.radius,
            maximumRadius: manager.maximumRegionMonitoringDistance
        )
        let mustBuffer = onTransition == nil || !pendingEvents.isEmpty || isDrainingPendingEvents
        // Logged only once the region is known to be ours: host-app identifiers must stay out of logs.
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
                // Emitted at drain, where ownership is first knowable; `buf=true` marks the delay.
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

    /// Movement-trigger EXITs re-centre on the attached coords, so freshen the fix first;
    /// fire-and-forget so a slow fix can't stall the pending-event drain.
    func dispatchTransition(
        identifier: String,
        transition: GeofenceTransition,
        capturedLocation: LocationData?,
        occurredAt: Date,
        circle: MonitoredCircle
    ) {
        if identifier == GeofenceConstants.movementTriggerIdentifier, transition == .exit {
            movementFixResolver.resolve(cached: bestKnownFix(), purpose: .pendingEvents) { [weak self] location, isFresh in
                self?.logger.geofenceCallbackDispatched(identifier: identifier, transition: transition)
                // The captured fallback is never current.
                self?.onTransition?(
                    identifier, transition, location ?? capturedLocation, occurredAt,
                    isFresh && location != nil, .circle(circle), true
                )
            }
            return
        }
        logger.geofenceCallbackDispatched(identifier: identifier, transition: transition)
        // Classic monitoring is silent at registration, so every region event is a crossing.
        onTransition?(identifier, transition, capturedLocation, occurredAt, false, eventCircle(circle, of: identifier), true)
    }

    /// The callback's own circle, or `.expired` when the OS now monitors a different circle under
    /// the id: a replaced region's event, which proves nothing about the current geometry. With no
    /// region monitored under the id, the callback's circle stands, as before.
    private func eventCircle(_ circle: MonitoredCircle, of identifier: String) -> GeofenceEventCircle {
        guard let current = monitoredRegion(manager, identifier) else { return .circle(circle) }
        let registered = MonitoredCircle(
            center: LocationData(latitude: current.center.latitude, longitude: current.center.longitude),
            radius: current.radius, maximumRadius: circle.maximumRadius
        )
        return registered.isSameCircle(as: circle) ? .circle(circle) : .expired
    }
}
