import CioInternalCommon
import CoreLocation
import Foundation

@available(iOS 17.0, *)
extension CLMonitorGeofenceMonitor {
    func adoptExistingRegions(matching identifiers: Set<String>, records: [String: MonitorRegionRecord]) {
        // Only owned, unstaged conditions: the bootstrap re-runs this from possibly stale storage,
        // and re-arming a just-evicted condition can push the OS over budget.
        let adopted = identifiers
            .intersection(knownConditionIdentifiers)
            .intersection(ownedRegionIdentifiers)
            .filter { conditionLedger.condition(for: $0) == nil }
        guard !adopted.isEmpty else { return }
        // Seeded before the re-arm drains, or a sync in that window re-adds every adopted region and
        // absorbs any undelivered crossing.
        for identifier in adopted {
            guard let record = records[identifier], let center = record.center, let radius = record.radius else { continue }
            // Already live at the OS, so confirmed from `.distantPast`.
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
        // A rejection still clears the OS side: ownership is already released, so a refused reshape
        // would leave its old circle holding an OS slot.
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

        // Synchronously, so a fast-arriving event isn't dropped.
        ownedRegionIdentifiers.insert(identifier)

        // Deprecated, but CLMonitor has no equivalent; matches the classic monitor's clamp.
        let clampedRadius = min(radius, authManager.maximumRegionMonitoringDistance)

        // The device's state seeds both `assuming:` and the stored baseline, so registration is silent.
        let stagedAt = dateUtil.now
        noteRegisteredCondition(
            identifier: identifier,
            center: LocationData(latitude: coordinate.latitude, longitude: coordinate.longitude),
            radius: clampedRadius,
            transitionTypes: transitionTypes,
            at: stagedAt
        )

        let isMovementTrigger = identifier == GeofenceConstants.movementTriggerIdentifier
        let side = deviceSide(center: coordinate, radius: clampedRadius)
        let isInside = side?.isInside ?? isMovementTrigger
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
                    // No fix, or one too old or too close to call, is an assumption: the ENTER the OS
                    // may answer it with is no crossing (see `MonitorRegionRecord.lastStateObserved`).
                    initialStateObserved: side?.isSettled ?? false,
                    stagedAt: stagedAt
                ),
                on: monitor
            )
        }
    }

    private struct StagedCondition {
        let identifier: String
        let center: LocationData
        let radius: Double
        let transitionTypes: Set<GeofenceTransition>
        let initialTransition: GeofenceTransition
        let assumedState: GeofenceConditionState
        let initialStateObserved: Bool
        let stagedAt: Date
    }

    private func installCondition(_ staged: StagedCondition, on monitor: GeofenceConditionMonitoring) async {
        let identifier = staged.identifier
        let center = staged.center
        let radius = staged.radius
        // Persist before the OS add: its corrective event must find this record. The reseed flag is
        // consumed here, not at staging: an add already queued when `.unmonitored` arrived drains
        // after it, so it must be the one to reseed.
        let forceReseed = conditionsNeedingBaselineReseed.remove(identifier) != nil
        await storage.recordMonitorRegistration(
            identifier: identifier,
            transitionTypes: staged.transitionTypes,
            initialState: staged.initialTransition,
            center: center,
            radius: radius,
            forceReseed: forceReseed,
            initialStateObserved: staged.initialStateObserved
        )
        // CLMonitor SILENTLY IGNORES an add over a live identifier, so always remove first.
        let readdStart = dateUtil.now
        await monitor.remove(identifier)
        // BEFORE the add: the OS dates its corrective as the add lands, and a later stamp would
        // attribute it to the replaced circle.
        let liveFrom = dateUtil.now
        await monitor.add(center: center, radius: radius, identifier: identifier, assuming: staged.assumedState)
        conditionLedger.confirm(identifier, stagedAt: staged.stagedAt, at: liveFrom)
        // Straight off the `add`: the contradiction gate's window starts here.
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

    private func releaseOwnership(_ identifier: String) {
        ownedRegionIdentifiers.remove(identifier)
        conditionsNeedingBaselineReseed.remove(identifier)
        conditionLedger.retire(identifier)
    }

    /// Keeps the storage record: a re-register relies on its baseline to suppress CLMonitor's
    /// re-evaluation of an unchanged state.
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
        conditionsNeedingBaselineReseed.removeAll()
        // CLMonitor's LIVE identifiers, not the owned/mirror snapshot, which can be lossy.
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
        // Also sweep CLMonitor's LIVE identifiers, so a lossy mirror can't strand a condition.
        enqueueMonitorOperation { [weak self] monitor in
            guard let self else { return }
            for identifier in await monitor.identifiers where !desiredIdentifiers.contains(identifier) {
                await monitor.remove(identifier)
                self.logger.geofenceConditionRemoved(identifier: identifier, op: .drop)
                self.knownConditionIdentifiers.remove(identifier)
            }
            self.persistConditionMirror()
        }
        // Before the loop below mutates ownership. The trigger's events aren't customer transitions.
        let healCandidates = regions
            .filter { $0.identifier != GeofenceConstants.movementTriggerIdentifier && isRegisteredUnchanged($0) }
            .map(\.identifier)
        var added: Set<String> = []
        for region in regions where !isRegisteredUnchanged(region) {
            // First, so a region `startMonitoring` rejects stops counting as registered.
            releaseOwnership(region.identifier)
            startMonitoring(
                identifier: region.identifier,
                center: region.center,
                radius: region.radius,
                transitionTypes: region.transitionTypes
            )
            // `startMonitoring` may have refused it; count only regions the OS took.
            if ownedRegionIdentifiers.contains(region.identifier) { added.insert(region.identifier) }
        }
        // After the adds above, so the heal drains behind this sync's own ops.
        enqueueBaselineHeal(candidates: healCandidates)
        let target = ConditionMirror.target(desired: desiredIdentifiers, owned: ownedRegionIdentifiers)
        logConditionMirrorDrift(desired: target.accepted, refused: target.refused, at: .sync)
        return GeofenceRegionDiff(added: added, removed: removed)
    }

    /// Must NOT consult `knownConditionIdentifiers`: it updates only at drain, so a region whose add
    /// is in flight would be re-registered.
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

    func eventCircle(for identifier: String, raisedAt: Date) -> GeofenceEventCircle {
        GeofenceEventCircle(
            conditionLedger.attribution(for: identifier, raisedAt: raisedAt),
            maximumRadius: authManager.maximumRegionMonitoringDistance
        )
    }
}
