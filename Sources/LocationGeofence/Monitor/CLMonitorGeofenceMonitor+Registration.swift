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
        logConditionMirrorDrift(desired: desiredIdentifiers, at: .sync)
        return GeofenceRegionDiff(added: added, removed: removed)
    }

    /// Samples the mirror on a slow timer as well, because the sync-time record cannot observe
    /// the failure it was written for: a record is only emitted by `setMonitoredRegions`, a sync
    /// only runs off a wake, and the failure IS the absence of wakes. Measured 09-17: the last
    /// reading landed ten seconds before region callbacks stopped and the next came two hours
    /// later, across a window where the process was demonstrably alive and taking visit callbacks.
    ///
    /// A sleep rather than a `Timer`: neither runs while the process is suspended, but an overdue
    /// sleep resumes on the next slice of runtime something else earns us — which is exactly when a
    /// sample is worth taking, and the only time one is possible. So the cadence below is a floor
    /// on the interval, never a guarantee, and a silent window yields as many samples as the
    /// process happened to be woken for.
    ///
    /// Each sample emits TWO records, and the split is the point. The beat is written synchronously
    /// here; the comparison against the OS has to run on the monitor pipeline, because
    /// `CLMonitor.identifiers` is only reachable from there. That pipeline is strictly serial, so
    /// one operation that never returns — or a `CLMonitor` that never finishes loading — silences
    /// every operation behind it, samples included. Region callbacks are read off the same actor,
    /// which makes "the pipeline is wedged" a candidate explanation for the exact 09-17 signature:
    /// process alive, visit callbacks arriving, region callbacks stopped. Beats without
    /// comparisons is that diagnosis; a probe reporting only through the pipeline could never
    /// make it.
    ///
    /// The task is process-lifetime by construction — the monitor is held in a `static let`, so
    /// `[weak self]` is the correct capture but never actually fires outside tests.
    func startConditionMirrorSampling() {
        guard GeofenceDiagnostics.isEnabled else { return }
        Task { [weak self] in
            // Monotonic, like every other elapsed value in the module: `Date()` steps under NTP
            // and would print a negative or wildly inflated gap in the one record whose entire job
            // is to be trusted about a gap. On Darwin it also counts while the process is
            // suspended, which is the interval being measured.
            var previousBeatAt = GeofenceLog.monotonicNow()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.conditionMirrorSampleNanos)
                guard let self else { return }
                let beatAt = GeofenceLog.monotonicNow()
                self.logger.geofenceInfo("condition_mirror_beat", fields: [
                    ("since", String(Int((beatAt - previousBeatAt).rounded()))),
                    ("want", String(self.conditionLedger.stagedIdentifiers.count))
                ])
                previousBeatAt = beatAt
                // The ledger, not the last `desired` set: a sample belongs to no sync generation,
                // and `stagedIdentifiers` is the standing answer to what this process wants held.
                self.logConditionMirrorDrift(desired: self.conditionLedger.stagedIdentifiers, at: .poll)
            }
        }
    }

    /// Records what CLMonitor itself holds against what THIS sync asked it to hold.
    ///
    /// Every registration record until now asserted our own belief: `monitoredRegionIdentifiers`
    /// returns `ownedRegionIdentifiers`, so `registration.adopted n=13` means "we think thirteen",
    /// never "the OS holds thirteen".
    ///
    /// `desired` is a captured value, never ownership. Ownership is the wrong side to compare: it
    /// is mutated synchronously by any later `setMonitoredRegions` whose OS work is still queued
    /// behind this record, and unioned into by `reconcileKnownConditions` on the first pipeline
    /// operation — so an ownership-based comparison reports healthy staged changes as drift in one
    /// direction or the other, whichever end it is read from. A sync passes its own set; the
    /// sampler passes the ledger's staged identifiers, which is the standing form of the same
    /// question. Both are read in the same synchronous turn that enqueues the OS work they
    /// describe, so the comparison below drains behind that work either way.
    ///
    /// `owned` rides alongside `want` because the two baselines disagree at process start and the
    /// difference is diagnostic, not noise: the ledger begins each process empty while ownership
    /// does not, so a condition the OS holds and we own, but which this process never staged —
    /// an adopted record with no geometry, or the `userChangedDuringBootstrap` branch — reads as
    /// `extra` on every sample until a sync re-registers it. With `owned` present a reader can
    /// tell that from "the OS is holding something nobody wants".
    ///
    /// `missing` is therefore precisely "this sync asked the OS for it and the OS does not list
    /// it". It is NOT a general "monitored by nobody" test: a condition the OS GAVE UP on stays
    /// listed in `CLMonitor.identifiers` (measured) and so never appears here. That case has its
    /// own record, from the `.unmonitored` branch in `process(event:)`; read the two together.
    func logConditionMirrorDrift(desired: Set<String>, at occasion: ConditionMirrorOccasion) {
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
                ("at", occasion.token),
                ("want", String(desired.count)),
                ("owned", String(self.ownedRegionIdentifiers.count)),
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

@available(iOS 17.0, *)
extension CLMonitorGeofenceMonitor {
    /// Floor on the sampling interval. Long enough that a drive costs a handful of records rather
    /// than one per fix, short enough that an 18-minute silent window is sampled repeatedly.
    static let conditionMirrorSampleNanos: UInt64 = 120000000000
}

/// Which occasion produced a `condition_mirror` record, so a reader can tell a sync's own
/// post-registration check from a sample taken while nothing was happening. Absent it, a clean
/// record during a silent window is indistinguishable from one emitted by a sync that had just run.
enum ConditionMirrorOccasion {
    case sync
    case poll

    /// Literals rather than a `String` raw value: a case rename then cannot silently change the
    /// emitted token, and the raw-value spelling is unwritable here anyway — SwiftFormat and
    /// SwiftLint both strip `case sync = "sync"`.
    var token: String {
        switch self {
        case .sync: return "sync"
        case .poll: return "poll"
        }
    }
}
