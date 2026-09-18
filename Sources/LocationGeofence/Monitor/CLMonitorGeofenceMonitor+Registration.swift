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
        rearmConditions(adopted, records: records)
        lastRearmAt = Date()
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
        let stagedAt = Date()
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
            let readdStart = Date()
            await monitor.remove(identifier)
            // Stamped BEFORE the add, not after it returns. The OS begins evaluating when the add
            // lands and dates its corrective event then, so a stamp taken afterwards puts every
            // corrective event BEFORE the generation that produced it — attributing it to the
            // circle just replaced, which the consumer's geometry guard then refuses. This is the
            // same window `ConditionReadd` keeps `start` and `added` apart for.
            let liveFrom = Date()
            await monitor.add(CLMonitor.CircularGeographicCondition(center: coordinate, radius: clampedRadius), identifier: identifier, assuming: assumedState)
            self.conditionLedger.confirm(identifier, stagedAt: stagedAt, at: liveFrom)
            self.conditionReadds[identifier] = ConditionReadd(
                start: readdStart,
                added: Date(),
                center: LocationData(latitude: coordinate.latitude, longitude: coordinate.longitude),
                radius: clampedRadius
            )
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
        logConditionMirrorDrift(desired: target.accepted, refused: target.refused)
        return GeofenceRegionDiff(added: added, removed: removed)
    }

    /// Records what CLMonitor itself holds against what THIS sync asked it to hold.
    ///
    /// Every registration record until now asserted our own belief: `monitoredRegionIdentifiers`
    /// returns `ownedRegionIdentifiers`, so `registration.adopted n=13` means "we think thirteen",
    /// never "the OS holds thirteen".
    ///
    /// Scoped to one sync generation on purpose, and that is what makes the fields truthful.
    /// Ownership is the wrong side to compare: it is mutated synchronously by any later
    /// `setMonitoredRegions` whose OS work is still queued behind this record, and unioned into by
    /// `reconcileKnownConditions` on the first pipeline operation — so an ownership-based
    /// comparison reports healthy staged changes as drift in one direction or the other,
    /// whichever end it is read from. `desired` is this call's own set and cannot move.
    ///
    /// `missing` is therefore precisely "this sync asked the OS for it and the OS does not list
    /// it". It is NOT a general "monitored by nobody" test: a condition the OS GAVE UP on stays
    /// listed in `CLMonitor.identifiers` (measured) and so never appears here. That case has its
    /// own record, from the `.unmonitored` branch in `process(event:)`; read the two together.
    func logConditionMirrorDrift(desired: Set<String>, refused: Int) {
        // Diagnostics-only work must cost normal users nothing. `geofenceInfo` drops the tail when
        // diagnostics are off, but the actor hop and set arithmetic below would still be queued on
        // the registration FIFO ahead of real monitor operations.
        guard GeofenceDiagnostics.isEnabled else { return }
        enqueueMonitorOperation { [weak self] monitor in
            guard let self else { return }
            // Drains after this sync's own adds and removes, so the OS should hold exactly
            // `desired` by now.
            let drift = ConditionMirror.drift(desired: desired, atOs: Set(await monitor.identifiers))
            self.logger.geofenceInfo("condition_mirror", fields: [
                ("want", String(desired.count)),
                // Quiet when nothing was turned down, like `missing` and `extra`, so the ordinary
                // record is unchanged and the key's presence is itself the signal.
                ("refused", refused > 0 ? String(refused) : nil),
                ("os", String(drift.atOsCount)),
                // `GeofenceLog.list`, not a plain join: these name conditions, and an identifier is
                // workspace-authored. The helper sanitizes each one and caps the list, where a raw
                // join would have the tail fold its own commas and turn two into one token.
                ("missing", GeofenceLog.list(drift.missing)),
                ("extra", GeofenceLog.list(drift.extra))
            ])
        }
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
}

/// The `condition_mirror` comparison, kept off the monitor so it carries no `@available` gate and
/// can be tested without a `CLMonitor` — which cannot be instantiated in a unit test.
enum ConditionMirror {
    /// What a sync actually asked the OS to hold, and how much of its request was refused.
    ///
    /// Ownership is the record of acceptance — it is inserted only once both of `startMonitoring`'s
    /// guards pass, and `setMonitoredRegions` has already released it for every identifier it no
    /// longer wants, so at the end of that loop ownership is exactly the accepted subset of
    /// `desired`. Intersecting rather than reading ownership directly keeps that a stated
    /// relationship instead of a coincidence, and keeps a refusal out of `missing` even if
    /// ownership later grows a member the desired set never had.
    ///
    /// `refused` is reported because scoping the comparison would otherwise hide those
    /// registrations completely, and only one of the two refusal paths says anything elsewhere.
    /// Unusable coordinates log `geofenceInvalidCoordinatesForRegion` per identifier; blocked
    /// permission logs an edge-triggered tier record that names no region and says nothing at all
    /// on a later sync while the tier is unchanged, and the registration diff counts a refused
    /// region in neither `added` nor `removed`. Without this field, N regions turned down by a
    /// blocked permission produce a perfectly clean record — which is a worse failure than the
    /// wrong attribution it replaced, because it is a silent one.
    struct Target: Equatable {
        let accepted: Set<String>
        let refused: Int
    }

    static func target(desired: Set<String>, owned: Set<String>) -> Target {
        let accepted = desired.intersection(owned)
        return Target(accepted: accepted, refused: desired.count - accepted.count)
    }

    /// Sorted so a capture diffs cleanly across passes.
    struct Drift: Equatable {
        let missing: [String]
        let extra: [String]
        let atOsCount: Int
    }

    static func drift(desired: Set<String>, atOs: Set<String>) -> Drift {
        Drift(
            missing: desired.subtracting(atOs).sorted(),
            extra: atOs.subtracting(desired).sorted(),
            atOsCount: atOs.count
        )
    }
}
