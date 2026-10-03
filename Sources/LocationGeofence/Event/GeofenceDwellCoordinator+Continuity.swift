import Foundation

/// Continuity across process relaunch, reboot, monitoring loss and location-access loss, split from
/// the coordinator's visit lifecycle so both stay under the file cap.
extension GeofenceDwellCoordinator {
    /// Resume persisted candidates after a process relaunch. A due deadline requests fresh
    /// evidence immediately; it does not itself prove the device remained inside. A visit from an
    /// earlier boot, recorded under more location access than there is now, or recorded by an
    /// earlier process under access that observes nothing in the background, is dropped instead:
    /// nothing watched the fence through the gap.
    func resumePendingVisits(geofences: [Geofence]) async {
        guard let userId = contextStore.currentUserId, !userId.isEmpty else { return }
        for geofence in geofences where tracksVisit(geofence) {
            if let visit = await currentVisit(geofence: geofence, userId: userId) {
                scheduleDeadline(for: geofence, visit: visit)
            }
        }
    }

    /// Monitoring stopped being trustworthy, so persisted entry time can no longer support a
    /// dwell. Pending deliveries remain untouched. Synchronous up to the returned removal, so the
    /// loss is dated when the caller saw it, not when a task got round to it.
    @discardableResult
    func interruptContinuity(geofenceId: String?) -> Task<Void, Never> {
        let lostAt = continuityLost(geofenceId: geofenceId)
        return Task { [weak self] in
            await self?.invalidateContinuity(geofenceId: geofenceId, lostAt: lostAt)
        }
    }

    /// Records that continuity was lost now, for one fence or (nil) every fence, and returns the
    /// instant. From here on, a visit write entered no later than it is refused.
    func continuityLost(geofenceId: String?) -> GeofenceClockReading {
        let reading = readClock()
        if let geofenceId {
            continuityLostUptime[geofenceId] = reading.uptime
        } else {
            allContinuityLostUptime = reading.uptime
        }
        return reading
    }

    /// Ends the continuity of the visits `lostAt` interrupted; nil means now. A visit entered
    /// after it, by a callback that ran before this did, is left alone.
    func invalidateContinuity(geofenceId: String? = nil, lostAt: GeofenceClockReading? = nil) async {
        let removed = await storage.removeDwellVisits(geofenceId: geofenceId, spanning: lostAt ?? readClock())
        for (id, visitId) in removed {
            cancelEvidence(for: id, ifVisit: visitId)
        }
    }

    /// Whether a loss recorded in this process happened at or after `visit` was entered: an
    /// interruption, or — for a visit recorded under access that observes nothing in the
    /// background — the app moving between foreground and background.
    func lossOvertook(_ visit: GeofenceDwellVisit, geofenceId: String) -> Bool {
        guard let timing = visit.timing else { return false }
        if identityTracker.interrupted(visit) { return true }
        var losses = [continuityLostUptime[geofenceId], allContinuityLostUptime]
        if Self.observesOnlyInForeground(visit) { losses.append(foregroundOnlyLostUptime) }
        guard let lostUptime = losses.compactMap({ $0 }).max() else { return false }
        return timing.enteredUptime <= lostUptime
    }

    /// Whether nothing known since `visit` was recorded has broken its continuity. Checked on
    /// every read and before a dwell is admitted, so a loss already recorded counts before the
    /// task removing the visit has run; and it catches a reboot or an access loss nothing
    /// reported, which iOS signals to no process that was not running.
    ///
    /// `ignoringLaterEnter` is only for a visit an EXIT already ended, judged up to that EXIT: the
    /// re-entry after it is a later stay, not a break in this one.
    func continuityHolds(for visit: GeofenceDwellVisit, geofenceId: String, ignoringLaterEnter: Bool = false) -> Bool {
        // No timing: recorded by a build that kept none, on a boot nothing identifies.
        guard let timing = visit.timing, timing.isCurrent(at: readClock()) else { return false }
        guard !lossOvertook(visit, geofenceId: geofenceId),
              ignoringLaterEnter || !enterSuperseded(visit, geofenceId: geofenceId)
        else { return false }
        // The app was not running for some time between processes, and under this access nothing
        // relaunches it for an EXIT.
        if Self.observesOnlyInForeground(visit), !visitsRecordedHere.contains(visit.visitId) { return false }
        if let recorded = visit.locationAccess, let current = currentLocationAccess(), current.isDowngrade(from: recorded) {
            return false
        }
        return true
    }

    /// The location access the app can use now: the permission, limited by Background App Refresh.
    func currentLocationAccess() -> GeofenceLocationAccess? {
        locationAccess?()?.limited(backgroundRefreshAvailable: backgroundRefreshAvailable?() ?? true)
    }

    /// Capture the loss in the notification callback, before a quick restoration can hide it
    /// from asynchronous revalidation. A repeated unavailable status interrupts no new visit.
    func backgroundRefreshChanged() {
        let available = backgroundRefreshAvailable?()
        if lastBackgroundRefreshAvailable == true, available == false {
            interruptContinuity(geofenceId: nil)
        } else {
            Task { await revalidateVisits() }
        }
        lastBackgroundRefreshAvailable = available
    }

    /// The app moved between foreground and background. A visit recorded under access that
    /// observes nothing in the background — When In Use, which holds no background session, or
    /// Always without Background App Refresh — cannot span that move: an EXIT in the background
    /// would not have reached the SDK. Dated now; the removal follows on a task. Under background
    /// delivery this changes nothing: suspension alone interrupts no monitoring.
    func foregroundChanged() {
        let reading = readClock()
        foregroundOnlyLostUptime = reading.uptime
        Task { [weak self] in
            guard let self else { return }
            let removed = await self.storage.removeDwellVisits { _, visit in
                Self.observesOnlyInForeground(visit) && (visit.timing?.spans(reading) ?? true)
            }
            for (id, visitId) in removed {
                self.cancelEvidence(for: id, ifVisit: visitId)
            }
        }
    }

    /// Reads every stored visit through `currentVisit`, which removes those whose continuity no
    /// longer holds. For a change in access iOS reports outside any authorization callback.
    func revalidateVisits() async {
        guard let userId = contextStore.currentUserId, !userId.isEmpty else { return }
        for geofence in await storage.getCachedGeofences() where tracksVisit(geofence) {
            _ = await currentVisit(geofence: geofence, userId: userId)
        }
    }

    /// A profile was identified. Identifying another user rewrites the identity without any
    /// reset, so visits recorded under an identity version no longer in force end: they must not be
    /// picked up again, as stays continuous across identities, when their user comes back. The
    /// tracker already refuses them; this removes them. Judged by version alone, so a late or
    /// replayed event, or a shifted wall clock, cannot remove a visit recorded since.
    func identityChanged() async {
        let tracker = identityTracker
        let removed = await storage.removeDwellVisits { _, visit in
            tracker.interrupted(visit)
        }
        for (id, visitId) in removed {
            cancelEvidence(for: id, ifVisit: visitId)
        }
    }

    /// Recorded under access whose region events stop outside the foreground. Unknown access
    /// (nil) is not assumed limited.
    static func observesOnlyInForeground(_ visit: GeofenceDwellVisit) -> Bool {
        visit.locationAccess.map { !$0.observesBackground } ?? false
    }
}
