import CioInternalCommon
import CoreLocation
import Foundation

/// Region registration for the CLMonitor path.
@available(iOS 17.0, *)
extension CLMonitorGeofenceMonitor {
    func adoptExistingRegions(matching identifiers: Set<String>, records: [String: MonitorRegionRecord]) {
        // Only conditions still owned and not yet staged. The bootstrap re-runs this on reconcile
        // drift and permission changes, from storage read before in-flight work landed; re-arming
        // conditions a sync had just evicted can push the OS over its budget, and it then gives up
        // on all of them.
        let adopted = identifiers
            .intersection(knownConditionIdentifiers)
            .intersection(ownedRegionIdentifiers)
            .filter { conditionLedger.condition(for: $0) == nil }
        guard !adopted.isEmpty else { return }
        // Seeded synchronously, before the queued re-arm drains, or a sync in that window reads
        // every adopted region as changed and re-adds it, absorbing any undelivered crossing. A
        // record without geometry stays unseeded and the next sync re-registers it.
        for identifier in adopted {
            guard let record = records[identifier], let center = record.center, let radius = record.radius else { continue }
            // Already live at the OS, so confirmed from `.distantPast` rather than awaiting a drain.
            noteRegisteredCondition(
                identifier: identifier,
                center: center,
                radius: radius,
                transitionTypes: record.transitionTypes,
                at: .distantPast,
                liveFrom: .distantPast
            )
        }
        rearmConditions(adopted)
        lastRearmAt = dateUtil.now
        logger.geofenceRegionsAdopted(identifiers: Array(adopted))
    }

    func startMonitoring(identifier: String, center: LocationData, radius: Double, transitionTypes: Set<GeofenceTransition>) {
        reportPermissionTier()
        // A rejected registration still clears the identifier at the OS. Re-registration releases
        // ownership first, so a refused reshape would otherwise leave its old circle holding an OS
        // slot with nothing owning it.
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

        // Parity with the classic monitor's clamp. `maximumRegionMonitoringDistance` is deprecated
        // but has no CLMonitor equivalent.
        let clampedRadius = min(radius, authManager.maximumRegionMonitoringDistance)

        // The device's actual state seeds both `assuming:` and the stored baseline, so registration
        // stays silent. No fix: the trigger is device-centred (inside), business geofences outside.
        // `dateUtil`, not `Date()`: the ledger confirm uses the same clock, which a replay overrides.
        let stagedAt = dateUtil.now
        noteRegisteredCondition(
            identifier: identifier,
            center: LocationData(latitude: coordinate.latitude, longitude: coordinate.longitude),
            radius: clampedRadius,
            transitionTypes: transitionTypes,
            at: stagedAt
        )

        let isMovementTrigger = identifier == GeofenceConstants.movementTriggerIdentifier
        let isInside = isDeviceInside(center: coordinate, radius: clampedRadius) ?? isMovementTrigger
        let initialTransition: GeofenceTransition = isInside ? .enter : .exit
        let assumedState: GeofenceConditionState = isInside ? .satisfied : .unsatisfied

        enqueueMonitorOperation { [weak self] monitor in
            guard let self else { return }
            await self.installCondition(
                StagedCondition(
                    identifier: identifier,
                    center: LocationData(latitude: coordinate.latitude, longitude: coordinate.longitude),
                    radius: clampedRadius,
                    transitionTypes: transitionTypes,
                    initialTransition: initialTransition,
                    assumedState: assumedState,
                    stagedAt: stagedAt
                ),
                on: monitor
            )
        }
    }

    /// One condition as `startMonitoring` resolved it: clamped, with its assumed state decided.
    private struct StagedCondition {
        let identifier: String
        let center: LocationData
        let radius: Double
        let transitionTypes: Set<GeofenceTransition>
        let initialTransition: GeofenceTransition
        let assumedState: GeofenceConditionState
        /// When the circle was staged, for the ledger's stage→confirm attribution window.
        let stagedAt: Date
    }

    /// Persists the record and puts the circle at the OS, on the monitor pipeline.
    private func installCondition(_ staged: StagedCondition, on monitor: GeofenceConditionMonitoring) async {
        let identifier = staged.identifier
        let center = staged.center
        let radius = staged.radius
        // Persist before the OS add: storage preserves the baseline on an unchanged circle and
        // reseeds on a new or changed one. The reseed flag is consumed here, not at staging: an add
        // already queued when `.unmonitored` arrived drains after it, so it must be the one to reseed.
        let forceReseed = conditionsNeedingBaselineReseed.remove(identifier) != nil
        await storage.recordMonitorRegistration(
            identifier: identifier,
            transitionTypes: staged.transitionTypes,
            initialState: staged.initialTransition,
            center: center,
            radius: radius,
            forceReseed: forceReseed
        )
        // CLMonitor SILENTLY IGNORES an add over a live identifier, keeping the original circle,
        // so it is always removed first; our bookkeeping can miss one the OS still holds.
        let readdStart = dateUtil.now
        await monitor.remove(identifier)
        // Stamped BEFORE the add: the OS dates its corrective event as the add lands, and a later
        // stamp would attribute that event to the circle just replaced.
        let liveFrom = dateUtil.now
        await monitor.add(center: center, radius: radius, identifier: identifier, assuming: staged.assumedState)
        conditionLedger.confirm(identifier, stagedAt: staged.stagedAt, at: liveFrom)
        // Stamped straight off the `add`: the contradiction gate's window starts here.
        let addedAt = dateUtil.now
        conditionReadds[identifier] = ConditionReadd(
            start: readdStart,
            added: addedAt,
            center: center,
            radius: radius
        )
        logger.geofenceConditionRemoved(identifier: identifier, op: .readd)
        logger.geofenceConditionAdded(identifier: identifier)
        knownConditionIdentifiers.insert(identifier)
        persistConditionMirror()
    }

    func stopMonitoring(identifier: String) {
        guard ownedRegionIdentifiers.contains(identifier) else { return }
        releaseOwnership(identifier)
        enqueueConditionRemoval(identifier)
    }

    /// Drops this process's claim on a condition without touching the OS.
    private func releaseOwnership(_ identifier: String) {
        ownedRegionIdentifiers.remove(identifier)
        // Nothing left to reseed for a condition this process no longer owns.
        conditionsNeedingBaselineReseed.remove(identifier)
        conditionLedger.retire(identifier)
    }

    /// Drops the condition at the OS. The storage record survives: a remove + re-register relies on
    /// the persisted baseline to suppress CLMonitor's re-evaluation of an unchanged state.
    private func enqueueConditionRemoval(_ identifier: String) {
        enqueueMonitorOperation { [weak self] monitor in
            guard let self else { return }
            await monitor.remove(identifier)
            self.logger.geofenceConditionRemoved(identifier: identifier, op: .drop)
            self.knownConditionIdentifiers.remove(identifier)
            self.persistConditionMirror()
        }
    }

    func stopMonitoringAll() {
        ownedRegionIdentifiers.removeAll()
        conditionLedger.forgetAll()
        // Teardown clears the stored records too (sign-out), so nothing is left to reseed.
        conditionsNeedingBaselineReseed.removeAll()
        // Clear against CLMonitor's LIVE identifiers, not the owned/mirror snapshot: an empty owned
        // set or a lossy mirror must not leave a stale SDK condition holding an OS slot.
        enqueueMonitorOperation { [weak self] monitor in
            guard let self else { return }
            for identifier in await monitor.identifiers {
                await monitor.remove(identifier)
                self.logger.geofenceConditionRemoved(identifier: identifier, op: .drop)
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
        // `stopMonitoring` above only reaches owned conditions. Sweep CLMonitor's LIVE identifiers
        // too, so a lossy mirror can't strand an SDK condition holding an OS slot.
        enqueueMonitorOperation { [weak self] monitor in
            guard let self else { return }
            for identifier in await monitor.identifiers where !desiredIdentifiers.contains(identifier) {
                await monitor.remove(identifier)
                self.logger.geofenceConditionRemoved(identifier: identifier, op: .drop)
                self.knownConditionIdentifiers.remove(identifier)
            }
            self.persistConditionMirror()
        }
        // Heal candidates: regions left registered-unchanged, evaluated before the loop below
        // mutates ownership. New registrations get the OS corrective from `assuming:`; the movement
        // trigger's events are internal control flow, not customer transitions.
        let healCandidates = regions
            .filter { $0.identifier != GeofenceConstants.movementTriggerIdentifier && isRegisteredUnchanged($0) }
            .map(\.identifier)
        var added: Set<String> = []
        for region in regions where !isRegisteredUnchanged(region) {
            // Release ownership first so a region `startMonitoring` rejects stops counting as
            // registered. On success it re-takes ownership in the same turn.
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
        // Enqueued after the adds above so the heal drains behind this sync's own ops.
        enqueueBaselineHeal(candidates: healCandidates)
        // Scoped to what the OS was actually asked for; see `ConditionMirror.Target`.
        let target = ConditionMirror.target(desired: desiredIdentifiers, owned: ownedRegionIdentifiers)
        logConditionMirrorDrift(desired: target.accepted, refused: target.refused, at: .sync)
        return GeofenceRegionDiff(added: added, removed: removed)
    }

    /// True when this monitor owns the condition and registered it with the same circle.
    ///
    /// Ownership plus the recorded circle is sufficient: every path that records geometry queues
    /// the matching OS add, and every path that invalidates the OS side clears one of them
    /// synchronously. `knownConditionIdentifiers` must NOT be consulted: it updates only at drain,
    /// so it would re-register (and risk absorbing a crossing on) any region whose add is in flight.
    private func isRegisteredUnchanged(_ region: GeofenceRegionRequest) -> Bool {
        guard ownedRegionIdentifiers.contains(region.identifier),
              let existing = conditionLedger.condition(for: region.identifier)
        else { return false }
        return region.matchesRegistered(
            center: existing.center,
            radius: existing.radius,
            transitionTypes: existing.transitionTypes,
            clampedTo: authManager.maximumRegionMonitoringDistance
        )
    }

    private func noteRegisteredCondition(
        identifier: String, center: LocationData, radius: Double,
        transitionTypes: Set<GeofenceTransition>, at registeredAt: Date, liveFrom: Date? = nil
    ) {
        conditionLedger.note(
            identifier: identifier, center: center, radius: radius,
            transitionTypes: transitionTypes, at: registeredAt, liveFrom: liveFrom
        )
    }

    /// The circle the OS raised an event against, chosen by the event's date; see
    /// `RegisteredConditionLedger.attribution(for:raisedAt:)`.
    func eventCircle(for identifier: String, raisedAt: Date) -> GeofenceEventCircle {
        GeofenceEventCircle(
            conditionLedger.attribution(for: identifier, raisedAt: raisedAt),
            maximumRadius: authManager.maximumRegionMonitoringDistance
        )
    }
}
