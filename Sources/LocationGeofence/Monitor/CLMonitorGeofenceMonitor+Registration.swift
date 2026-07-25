import CioInternalCommon
import CoreLocation
import Foundation

/// Region registration for the CLMonitor path, split out to keep the monitor's event and lifecycle
/// plumbing readable. Members are `internal` (not `private`) only because they live in a separate
/// file from their state; they remain monitor implementation detail.
@available(iOS 17.0, *)
extension CLMonitorGeofenceMonitor {
    func adoptExistingRegions(matching identifiers: Set<String>) {
        let adopted = identifiers.intersection(knownConditionIdentifiers)
        guard !adopted.isEmpty else { return }
        ownedRegionIdentifiers.formUnion(adopted)
        rearmConditions(adopted)
        logger.geofenceRegionsAdopted(count: adopted.count)
    }

    func startMonitoring(identifier: String, center: LocationData, radius: Double, transitionTypes: Set<GeofenceTransition>) {
        reportPermissionTier()
        guard CoreLocationGeofenceMonitor.permissionTier(for: authManager.authorizationStatus) != .blocked else { return }

        let coordinate = CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude)
        guard CLLocationCoordinate2DIsValid(coordinate) else {
            logger.geofenceInvalidCoordinatesForRegion(identifier)
            return
        }

        // Populate the ownership filter synchronously so a fast-arriving event isn't dropped.
        ownedRegionIdentifiers.insert(identifier)

        // Parity with the classic monitor's clamp; `maximumRegionMonitoringDistance` is a deprecated
        // but harmless read with no CLMonitor equivalent — both paths register identical geometry.
        let clampedRadius = min(radius, authManager.maximumRegionMonitoringDistance)

        // The device's ACTUAL state seeds both CLMonitor's `assuming:` hint and the stored baseline
        // (see `recordMonitorRegistration`: registration stays silent, the first real crossing
        // delivers). No fix → geometric expectation: trigger is device-centered (inside),
        // business geofences outside.
        noteRegisteredCondition(
            identifier: identifier,
            center: LocationData(latitude: coordinate.latitude, longitude: coordinate.longitude),
            radius: clampedRadius,
            transitionTypes: transitionTypes
        )

        let isMovementTrigger = identifier == GeofenceConstants.movementTriggerIdentifier
        let isInside = isDeviceInside(center: coordinate, radius: clampedRadius) ?? isMovementTrigger
        let initialTransition: GeofenceTransition = isInside ? .enter : .exit
        let assumedState: CLMonitor.Event.State = isInside ? .satisfied : .unsatisfied

        enqueueMonitorOperation { [weak self] monitor in
            guard let self else { return }
            // Persist before the OS add: storage keys off recorded geometry to preserve the baseline
            // on an unchanged re-register and reseed on a new/changed circle. The decision lives in
            // storage because this runs after stop-all, when CLMonitor's own record is already gone.
            await self.storage.recordMonitorRegistration(
                identifier: identifier,
                transitionTypes: transitionTypes,
                initialState: initialTransition,
                center: LocationData(latitude: coordinate.latitude, longitude: coordinate.longitude),
                radius: clampedRadius
            )
            let condition = CLMonitor.CircularGeographicCondition(center: coordinate, radius: clampedRadius)
            await monitor.add(condition, identifier: identifier, assuming: assumedState)
            self.knownConditionIdentifiers.insert(identifier)
            self.persistConditionMirror()
        }
    }

    func stopMonitoring(identifier: String) {
        guard ownedRegionIdentifiers.remove(identifier) != nil else { return }
        registeredConditions.removeValue(forKey: identifier)
        enqueueConditionRemoval(identifier)
    }

    /// Drops the condition at the OS. Split from `stopMonitoring` because re-registration must be
    /// able to clear a condition this process has not adopted — see `setMonitoredRegions`.
    ///
    /// The storage record intentionally survives removal: a remove + re-register cycle relies on
    /// the persisted baseline to suppress CLMonitor's re-evaluation of an unchanged state.
    private func enqueueConditionRemoval(_ identifier: String) {
        enqueueMonitorOperation { [weak self] monitor in
            guard let self else { return }
            await monitor.remove(identifier)
            self.knownConditionIdentifiers.remove(identifier)
            self.persistConditionMirror()
        }
    }

    func stopMonitoringAll() {
        ownedRegionIdentifiers.removeAll()
        registeredConditions.removeAll()
        // Clear against CLMonitor's LIVE identifiers, not the owned/mirror snapshot: an empty owned
        // set or a lossy mirror must not leave a stale SDK condition holding an OS slot.
        enqueueMonitorOperation { [weak self] monitor in
            guard let self else { return }
            for identifier in await monitor.identifiers {
                await monitor.remove(identifier)
            }
            self.knownConditionIdentifiers.removeAll()
            self.persistConditionMirror()
        }
    }

    @discardableResult
    func setMonitoredRegions(_ regions: [GeofenceRegionRequest]) -> GeofenceRegionDiff {
        let desiredIdentifiers = Set(regions.map(\.identifier))
        var removed: Set<String> = []
        for identifier in ownedRegionIdentifiers.subtracting(desiredIdentifiers) {
            stopMonitoring(identifier: identifier)
            removed.insert(identifier)
        }
        // `stopMonitoring` above only reaches conditions this process knows it owns. Sweep the rest
        // against CLMonitor's LIVE identifiers, the job `stopMonitoringAll` used to do wholesale, so
        // a lossy mirror can't strand an SDK condition holding an OS slot.
        enqueueMonitorOperation { [weak self] monitor in
            guard let self else { return }
            for identifier in await monitor.identifiers where !desiredIdentifiers.contains(identifier) {
                await monitor.remove(identifier)
                self.knownConditionIdentifiers.remove(identifier)
            }
            self.persistConditionMirror()
        }
        var added: Set<String> = []
        for region in regions where !isRegisteredUnchanged(region) {
            // CLMonitor SILENTLY IGNORES an add over a live identifier — it keeps the original
            // circle and reports no error — so a reshaped region must be removed first; the
            // pipeline is FIFO, so the remove lands before the add. `stopMonitoring` only reaches
            // regions this process owns, and a condition the OS holds that adoption missed would
            // otherwise keep its old circle forever: the add is dropped, but the new geometry is
            // still recorded here, so every later pass reads "unchanged" and never repairs it.
            if ownedRegionIdentifiers.contains(region.identifier) {
                stopMonitoring(identifier: region.identifier)
            } else if knownConditionIdentifiers.contains(region.identifier) {
                enqueueConditionRemoval(region.identifier)
            }
            startMonitoring(
                identifier: region.identifier,
                center: region.center,
                radius: region.radius,
                transitionTypes: region.transitionTypes
            )
            // Blocked permission / invalid coordinates make `startMonitoring` a no-op; the caller's
            // initial-enter decision must not count a region the OS never took.
            if ownedRegionIdentifiers.contains(region.identifier) { added.insert(region.identifier) }
        }
        return GeofenceRegionDiff(added: added, removed: removed)
    }

    /// True when this monitor owns the condition and registered it with the same circle, so
    /// re-adding would only risk absorbing an undelivered crossing.
    private func isRegisteredUnchanged(_ region: GeofenceRegionRequest) -> Bool {
        guard ownedRegionIdentifiers.contains(region.identifier),
              knownConditionIdentifiers.contains(region.identifier),
              let existing = registeredConditions[region.identifier]
        else { return false }
        return region.matchesRegistered(
            center: existing.center,
            radius: existing.radius,
            transitionTypes: existing.transitionTypes,
            clampedTo: authManager.maximumRegionMonitoringDistance
        )
    }

    /// Records the circle a condition now holds. Internal for the `+Rearm` extension, which re-adds
    /// conditions from persisted records.
    func noteRegisteredCondition(identifier: String, center: LocationData, radius: Double, transitionTypes: Set<GeofenceTransition>) {
        registeredConditions[identifier] = RegisteredCondition(
            center: center,
            radius: radius,
            transitionTypes: transitionTypes
        )
    }
}
