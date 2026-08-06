import CioInternalCommon
import CoreLocation
import Foundation

/// Region registration for the CLMonitor path, split out to keep the monitor's event and lifecycle
/// plumbing readable. Members are `internal` (not `private`) only because they live in a separate
/// file from their state; they remain monitor implementation detail.
@available(iOS 17.0, *)
extension CLMonitorGeofenceMonitor {
    func adoptExistingRegions(matching identifiers: Set<String>, records: [String: MonitorRegionRecord]) {
        let adopted = identifiers.intersection(knownConditionIdentifiers)
        guard !adopted.isEmpty else { return }
        ownedRegionIdentifiers.formUnion(adopted)
        // Seed the geometry map synchronously, before the queued re-arm drains: a sync landing in
        // that window would otherwise read every adopted region as changed (no recorded circle)
        // and remove + re-add them all — absorbing any crossing the OS has detected but not yet
        // delivered. Seeded from the same records the re-arm imposes at the OS, so the diff
        // compares against what the OS will hold once it drains. A record without geometry stays
        // unseeded and the next sync re-registers it, matching `rearmConditions`.
        for identifier in adopted {
            guard let record = records[identifier], let center = record.center, let radius = record.radius else { continue }
            noteRegisteredCondition(
                identifier: identifier,
                center: center,
                radius: radius,
                transitionTypes: record.transitionTypes
            )
        }
        rearmConditions(adopted, records: records)
        logger.geofenceRegionsAdopted(count: adopted.count)
    }

    func startMonitoring(identifier: String, center: LocationData, radius: Double, transitionTypes: Set<GeofenceTransition>) {
        reportPermissionTier()
        // A rejected registration still clears the identifier at the OS. Re-registration releases
        // ownership before calling in, so without this a reshaped region that is refused would leave
        // its previous circle live and holding one of the 20 OS slots — with nothing owning it, no
        // later pass repairs it while the region stays in the desired set.
        guard CoreLocationGeofenceMonitor.permissionTier(for: authManager.authorizationStatus) != .blocked else {
            enqueueConditionRemoval(identifier)
            return
        }

        let coordinate = CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude)
        guard CLLocationCoordinate2DIsValid(coordinate) else {
            logger.geofenceInvalidCoordinatesForRegion(identifier)
            enqueueConditionRemoval(identifier)
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
            // Consumed here rather than at staging time: an add already queued when `.unmonitored`
            // arrived still drains after it, so it is the one that must reseed.
            let forceReseed = self.conditionsNeedingBaselineReseed.remove(identifier) != nil
            await self.storage.recordMonitorRegistration(
                identifier: identifier,
                transitionTypes: transitionTypes,
                initialState: initialTransition,
                center: LocationData(latitude: coordinate.latitude, longitude: coordinate.longitude),
                radius: clampedRadius,
                forceReseed: forceReseed
            )
            // CLMonitor SILENTLY IGNORES an add over a live identifier, keeping the original circle
            // and reporting no error, so the identifier is cleared first. Keyed on the OS rather
            // than on this process's bookkeeping, which can be missing an identifier the OS still
            // holds. Removing one the OS does not hold is a no-op.
            await monitor.remove(identifier)
            let condition = CLMonitor.CircularGeographicCondition(center: coordinate, radius: clampedRadius)
            await monitor.add(condition, identifier: identifier, assuming: assumedState)
            self.knownConditionIdentifiers.insert(identifier)
            self.persistConditionMirror()
        }
    }

    func stopMonitoring(identifier: String) {
        guard ownedRegionIdentifiers.contains(identifier) else { return }
        releaseOwnership(identifier)
        enqueueConditionRemoval(identifier)
    }

    /// Drops this process's claim on a condition without touching the OS.
    private func releaseOwnership(_ identifier: String) {
        ownedRegionIdentifiers.remove(identifier)
        registeredConditions.removeValue(forKey: identifier)
    }

    /// Drops the condition at the OS.
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
        // Teardown clears the stored records too (sign-out), so nothing is left to reseed.
        conditionsNeedingBaselineReseed.removeAll()
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
            // Release ownership first so a region `startMonitoring` rejects (blocked permission,
            // invalid coordinates) stops counting as registered instead of keeping the claim it
            // held before the change. `startMonitoring` re-takes it in the same turn on success,
            // and clears the identifier at the OS from inside its queued add.
            releaseOwnership(region.identifier)
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
    ///
    /// Ownership plus the recorded circle is sufficient: every path that records geometry also
    /// queues the matching OS add on the FIFO, and every path that invalidates the OS side clears
    /// ownership or the record synchronously. `knownConditionIdentifiers` must NOT be consulted —
    /// it is only updated when queued operations drain, so requiring it re-registers any region
    /// whose add is still in flight — staged either by a sync that landed before an earlier one's
    /// operations drained or by the launch re-arm. Each is an absorbing remove + add for a circle
    /// the OS already holds or is about to.
    private func isRegisteredUnchanged(_ region: GeofenceRegionRequest) -> Bool {
        guard ownedRegionIdentifiers.contains(region.identifier),
              let existing = registeredConditions[region.identifier]
        else { return false }
        return region.matchesRegistered(
            center: existing.center,
            radius: existing.radius,
            transitionTypes: existing.transitionTypes,
            clampedTo: authManager.maximumRegionMonitoringDistance
        )
    }

    /// Records the circle a condition now holds.
    private func noteRegisteredCondition(identifier: String, center: LocationData, radius: Double, transitionTypes: Set<GeofenceTransition>) {
        registeredConditions[identifier] = RegisteredCondition(
            center: center,
            radius: radius,
            transitionTypes: transitionTypes
        )
    }
}
