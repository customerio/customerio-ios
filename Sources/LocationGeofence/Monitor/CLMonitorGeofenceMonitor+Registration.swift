import CioInternalCommon
import CoreLocation
import Foundation

/// Region registration for the CLMonitor path, split out to keep the monitor's event and lifecycle
/// plumbing readable. Members are `internal` (not `private`) only because they live in a separate
/// file from their state; they remain monitor implementation detail.
@available(iOS 17.0, *)
extension CLMonitorGeofenceMonitor {
    func adoptExistingRegions(matching identifiers: Set<String>, records: [String: MonitorRegionRecord]) {
        // Only conditions this process still owns and has not already staged. The bootstrap re-runs
        // this on reconcile drift and on permission changes, from storage read before in-flight work
        // has landed. On the 2026-09-12 relaunch that second run re-armed the previous session's
        // twenty conditions — two of them a sync had just evicted, their removes still queued ahead —
        // put the OS over its condition budget, and CoreLocation gave all twenty up. A condition
        // released by `stopMonitoring` is no longer owned; one adopted or registered in this process
        // already has a geometry entry. Either way a second adopt has nothing left to do.
        let adopted = identifiers
            .intersection(knownConditionIdentifiers)
            .intersection(ownedRegionIdentifiers)
            .filter { conditionLedger.condition(for: $0) == nil }
        guard !adopted.isEmpty else { return }
        // Seed the geometry map synchronously, before the queued re-arm drains: a sync landing in
        // that window would otherwise read every adopted region as changed (no recorded circle)
        // and remove + re-add them all — absorbing any crossing the OS has detected but not yet
        // delivered. Seeded from the same records the re-arm imposes at the OS, so the diff
        // compares against what the OS will hold once it drains. A record without geometry stays
        // unseeded and the next sync re-registers it, matching `rearmConditions`.
        for identifier in adopted {
            guard let record = records[identifier], let center = record.center, let radius = record.radius else { continue }
            // Already live at the OS — adoption is the case where the condition outlived the
            // process — so it is confirmed from `.distantPast` rather than awaiting a drain.
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
        // `dateUtil`, not `Date()`: the confirm side of this stage reads the injected clock, and a
        // replay that overrides it would otherwise compare a virtual confirm against a wall-clock
        // stage and attribute the pair to two different timelines.
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
    ///
    /// Extracted from `startMonitoring` only to keep that function readable; it has no other caller
    /// and no meaning outside the enqueued operation it runs in.
    private func installCondition(_ staged: StagedCondition, on monitor: GeofenceConditionMonitoring) async {
        let identifier = staged.identifier
        let center = staged.center
        let radius = staged.radius
        // Persist before the OS add: storage keys off recorded geometry to preserve the baseline
        // on an unchanged re-register and reseed on a new/changed circle. The decision lives in
        // storage because this runs after stop-all, when CLMonitor's own record is already gone.
        // Consumed here rather than at staging time: an add already queued when `.unmonitored`
        // arrived still drains after it, so it is the one that must reseed.
        let forceReseed = conditionsNeedingBaselineReseed.removeValue(forKey: identifier) != nil
        await storage.recordMonitorRegistration(
            identifier: identifier,
            transitionTypes: staged.transitionTypes,
            initialState: staged.initialTransition,
            center: center,
            radius: radius,
            forceReseed: forceReseed
        )
        // CLMonitor SILENTLY IGNORES an add over a live identifier, keeping the original circle
        // and reporting no error, so the identifier is cleared first. Keyed on the OS rather
        // than on this process's bookkeeping, which can be missing an identifier the OS still
        // holds. Removing one the OS does not hold is a no-op.
        let readdStart = dateUtil.now
        await monitor.remove(identifier)
        // Stamped BEFORE the add, not after it returns. The OS begins evaluating when the add lands
        // and dates its corrective event then, so a stamp taken afterwards puts every corrective
        // event BEFORE the generation that produced it — attributing it to the circle just replaced,
        // which the consumer's geometry guard then refuses.
        let liveFrom = dateUtil.now
        await monitor.add(center: center, radius: radius, identifier: identifier, assuming: staged.assumedState)
        conditionLedger.confirm(identifier, stagedAt: staged.stagedAt, at: liveFrom)
        // Stamped straight off the `add`, before anything else runs. The contradiction gate replays
        // events against this instant, and a log dispatched between the two pushes the anchor later
        // than the OS actually accepted the circle.
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
        // The region is leaving the desired set, so there is nothing left to reseed and nothing
        // left to refuse events for. Left behind, the flag keeps `pending` non-zero for a condition
        // no recovery will ever re-register, and every later burst is rate-limited behind it.
        conditionsNeedingBaselineReseed.removeValue(forKey: identifier)
        conditionLedger.retire(identifier)
    }

    /// Drops the condition at the OS.
    ///
    /// The storage record intentionally survives removal: a remove + re-register cycle relies on
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
        // `stopMonitoring` above only reaches conditions this process knows it owns. Sweep the rest
        // against CLMonitor's LIVE identifiers, the job `stopMonitoringAll` used to do wholesale, so
        // a lossy mirror can't strand an SDK condition holding an OS slot.
        enqueueMonitorOperation { [weak self] monitor in
            guard let self else { return }
            for identifier in await monitor.identifiers where !desiredIdentifiers.contains(identifier) {
                await monitor.remove(identifier)
                self.logger.geofenceConditionRemoved(identifier: identifier, op: .drop)
                self.knownConditionIdentifiers.remove(identifier)
            }
            self.persistConditionMirror()
        }
        // Heal candidates: regions this sync leaves registered-unchanged (evaluated at entry,
        // before the loop below mutates ownership for the changed ones). Newly-registered regions
        // are excluded — their staged `assuming:` already provokes the OS corrective — as is the
        // movement trigger, whose events are internal control flow, not customer transitions.
        let healCandidates = regions
            .filter { $0.identifier != GeofenceConstants.movementTriggerIdentifier && isRegisteredUnchanged($0) }
            .map(\.identifier)
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
        // Enqueued after the adds above so the heal drains behind this sync's own ops.
        enqueueBaselineHeal(candidates: healCandidates)
        // Scoped to what the OS was actually asked for. `desiredIdentifiers` is the caller's
        // request, and `startMonitoring` refuses part of it — blocked permission, unusable
        // coordinates — by removing the condition and returning before it takes ownership. Those
        // identifiers never reach the OS, so reporting them as `missing` blames the OS for a
        // refusal this SDK made, in the record whose whole purpose is separating the two.
        let target = ConditionMirror.target(desired: desiredIdentifiers, owned: ownedRegionIdentifiers)
        logConditionMirrorDrift(desired: target.accepted, refused: target.refused, at: .sync)
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
              let existing = conditionLedger.condition(for: region.identifier)
        else { return false }
        return region.matchesRegistered(
            center: existing.center,
            radius: existing.radius,
            transitionTypes: existing.transitionTypes,
            clampedTo: authManager.maximumRegionMonitoringDistance
        )
    }

    /// Records the circle a condition now holds.
    private func noteRegisteredCondition(
        identifier: String, center: LocationData, radius: Double,
        transitionTypes: Set<GeofenceTransition>, at registeredAt: Date, liveFrom: Date? = nil
    ) {
        conditionLedger.note(
            identifier: identifier, center: center, radius: radius,
            transitionTypes: transitionTypes, at: registeredAt, liveFrom: liveFrom
        )
    }

    /// The circle the OS raised an event against, chosen by the event's own date rather than by
    /// what is registered now: `CLMonitor` events are read off an async stream, so a refresh can
    /// replace the condition between the daemon raising an event and this monitor dequeuing it.
    /// Reading only the current map would report the replacement and let a stale event look
    /// current — the one case a consumer comparing circles is trying to catch.
    func eventCircle(for identifier: String, raisedAt: Date) -> GeofenceEventCircle {
        GeofenceEventCircle(
            conditionLedger.attribution(for: identifier, raisedAt: raisedAt),
            maximumRadius: authManager.maximumRegionMonitoringDistance
        )
    }

    /// CLMonitor gave up on the condition: drop the mirror entry, circle and baseline so it is
    /// re-registered. Ownership is kept on purpose; dropping it would strand the region.
    ///
    /// Two halves run on different timelines, which is why events for the condition are refused
    /// outright until it is re-registered (`isAwaitingReregistration`): the baseline clear below is
    /// queued behind every pending OS op, while the gate stamp goes synchronously, so a daemon
    /// replay landing in that gap would be judged against a stale baseline with no gate. And the
    /// re-registration is scheduled here rather than left to "the next sync", because syncs are
    /// driven by the movement trigger, which may itself be among the conditions given up.
    func handleConditionUnmonitored(_ identifier: String) {
        logger.geofenceMonitorStoppedMonitoringRegion(identifier)
        knownConditionIdentifiers.remove(identifier)
        conditionLedger.forget(identifier)
        conditionReadds.removeValue(forKey: identifier)
        // A same-circle re-registration preserves state by design; after the OS gave up it must not.
        conditionsNeedingBaselineReseed[identifier] = dateUtil.now
        persistConditionMirror()
        // Skipped if a registration re-added the identifier meanwhile; keyed on this monitor's own
        // adds because `CLMonitor.identifiers` still lists a condition the OS gave up on.
        enqueueMonitorOperation { [weak self] _ in
            guard let self, !self.knownConditionIdentifiers.contains(identifier) else { return }
            await self.storage.clearMonitorRegionRecord(identifier: identifier)
        }
        scheduleUnmonitoredRecovery()
    }

    /// Re-registers what the OS gave up on, without waiting for a movement pass.
    ///
    /// The handler above used to leave recovery to "the next sync", and the next sync is driven by
    /// the movement trigger. On the 2026-09-12 relaunch the trigger was among the conditions given
    /// up, so no sync could come: the phone drove 4.2 km over the next 66 minutes with the module
    /// frozen, and two fences' enters and exits were lost, until a sign-out reset it. This queues one
    /// re-run of the bootstrap behind the ops already in flight — the route a mirror drift already
    /// takes — which finds the given-up identifiers missing from the OS set and re-registers exactly
    /// those, with a reseeded baseline. One per burst: a storm of twenty schedules one run. And rate
    /// limited, so a condition the OS refuses to hold (a host app over the budget) cannot loop.
    func scheduleUnmonitoredRecovery() {
        guard !isUnmonitoredRecoveryScheduled else { return }
        if let last = lastUnmonitoredRecoveryAt {
            let sinceLast = dateUtil.now.timeIntervalSince(last)
            if sinceLast < GeofenceConstants.unmonitoredRecoveryInterval {
                deferUnmonitoredRecovery(by: GeofenceConstants.unmonitoredRecoveryInterval - sinceLast)
                return
            }
        }
        isUnmonitoredRecoveryScheduled = true
        enqueueMonitorOperation { [weak self] _ in
            guard let self else { return }
            self.isUnmonitoredRecoveryScheduled = false
            // A registration that drained meanwhile has already consumed the flags.
            let pending = self.conditionsNeedingBaselineReseed.count
            guard pending > 0 else { return }
            // Stamped only now, after the work is known to be real. Stamping on entry meant a run
            // that found nothing pending still burned the window, and the genuine burst arriving
            // ten seconds later was refused by a rate limit that had guarded nothing.
            self.lastUnmonitoredRecoveryAt = self.dateUtil.now
            self.logger.geofenceUnmonitoredRecovery(count: pending)
            self.onReconciled?()
        }
    }

    /// Re-asks once the rate-limit window has passed.
    ///
    /// Returning instead — which is what this used to do — assumed something else would come along
    /// to notice. Nothing necessarily will: syncs are driven by the movement trigger, and on the
    /// 2026-09-12 relaunch the trigger was itself among the conditions the OS gave up. A burst
    /// thirty seconds after a recovery was therefore discarded outright, leaving exactly the frozen
    /// module this recovery exists to prevent.
    private func deferUnmonitoredRecovery(by delay: TimeInterval) {
        guard !isUnmonitoredRecoveryDeferred else { return }
        isUnmonitoredRecoveryDeferred = true
        Task { @MainActor [weak self, waitForRecoveryWindow] in
            await waitForRecoveryWindow(delay)
            guard let self else { return }
            self.isUnmonitoredRecoveryDeferred = false
            self.scheduleUnmonitoredRecovery()
        }
    }
}
