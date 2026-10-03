import CioInternalCommon
import CoreLocation
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Deadline and retry scheduling for dwell evidence, split from the coordinator's visit lifecycle
/// so both stay under the file cap. Members are `internal` rather than `private` only because of
/// this split; they remain implementation detail of an internal type.
extension GeofenceDwellCoordinator {
    struct EvidenceRetryState {
        let visitId: String
        var attempts: Int
    }

    func scheduleDeadline(for geofence: Geofence, visit: GeofenceDwellVisit) {
        deadlineTasks.removeValue(forKey: geofence.id)?.cancel()
        evidenceRetries[geofence.id] = EvidenceRetryState(visitId: visit.visitId, attempts: 0)
        guard geofence.dwellThresholdSeconds > 0, !visit.emitted else {
            cancelEvidence(for: geofence.id)
            return
        }
        // Elapsed as qualifying measures it, so a wall-clock step moves the deadline no more than
        // it moves qualification.
        // A candidate awaiting proof asks for it at once: its time has not started. So does a
        // reserved dwell, which only repeats its reservation; across an ambiguous boot no elapsed
        // time is known to count down from.
        let now = readClock()
        let elapsed = visit.timing?.elapsed(enteredAt: visit.enteredAt, until: now.wall, at: now)?.qualifyingSeconds ?? 0
        let delay = visit.awaitsPresenceProof || visit.dwellReservation != nil ? 0 : min(
            TimeInterval(GeofenceDwellLimits.maxThresholdSeconds),
            max(0, TimeInterval(geofence.dwellThresholdSeconds) - elapsed)
        )
        let delayNanoseconds = UInt64(delay * 1000000000)
        deadlineTasks[geofence.id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled, let self else { return }
            await self.requestQualifyingEvidence(geofenceId: geofence.id)
        }
    }

    func requestQualifyingEvidence(geofenceId: String) async {
        guard !Task.isCancelled,
              let geofence = await storage.getRegisteredGeofence(id: geofenceId),
              !Task.isCancelled,
              let expectedUserId = contextStore.currentUserId, !expectedUserId.isEmpty,
              let visit = await activeVisit(geofence: geofence, userId: expectedUserId),
              !Task.isCancelled
        else {
            cancelEvidence(for: geofenceId)
            return
        }
        if visit.dwellReservation != nil {
            // A reserved dwell whose delivery did not complete — a failed write, or a relaunch —
            // is repeated as reserved; fresh evidence would describe a different instant.
            await deliverReservedDwell(geofence: geofence, visit: visit, userId: expectedUserId)
            await retryIfStillPending(geofence: geofence, visitId: visit.visitId, expectedUserId: expectedUserId)
        } else if geofence.vertices != nil {
            await requestPolygonEvidence(geofence: geofence, visit: visit, expectedUserId: expectedUserId)
        } else {
            await requestCircleEvidence(geofence: geofence, visit: visit, expectedUserId: expectedUserId)
        }
    }

    /// A polygon's membership is decided by the resolver against the real shape; its verdict
    /// reaches this coordinator as inside evidence, not through this call's return.
    private func requestPolygonEvidence(
        geofence: Geofence,
        visit: GeofenceDwellVisit,
        expectedUserId: String
    ) async {
        guard let polygonVerifier else {
            scheduleEvidenceRetry(for: geofence, visit: visit)
            return
        }
        await polygonVerifier(geofence.id)
        await retryIfStillPending(geofence: geofence, visitId: visit.visitId, expectedUserId: expectedUserId)
    }

    private func requestCircleEvidence(
        geofence: Geofence,
        visit: GeofenceDwellVisit,
        expectedUserId: String
    ) async {
        let fix = await freshFix()
        guard !Task.isCancelled,
              contextStore.currentUserId == expectedUserId,
              let remaining = await activeVisit(
                  geofence: geofence, userId: expectedUserId, visitId: visit.visitId
              ),
              !Task.isCancelled
        else { return }
        guard let fix else {
            scheduleEvidenceRetry(for: geofence, visit: remaining)
            return
        }
        switch circleVerdict(of: fix, for: geofence) {
        case .outside:
            if await !endContinuity(of: remaining, geofence: geofence, observedOutsideAt: fix.timestamp) {
                scheduleEvidenceRetry(for: geofence, visit: remaining)
            }
            return
        case .undecided:
            // Teardown is left to Core Location's real EXIT.
            scheduleEvidenceRetry(for: geofence, visit: remaining)
            return
        case .inside:
            break
        }
        await recordInsideEvidence(
            geofence: geofence,
            at: fix.timestamp,
            source: "location_evidence",
            expectedUserId: expectedUserId,
            // An EXIT can land during the storage hops before this is applied. The fix predates
            // it, so it must not start a new visit that outlives the exit.
            continuingVisitId: visit.visitId
        )
        await retryIfStillPending(geofence: geofence, visitId: visit.visitId, expectedUserId: expectedUserId)
    }

    /// What a fix proves about a circle. The point alone is not a verdict: only an accuracy circle
    /// wholly inside the region is qualifying dwell evidence, and only one wholly outside it is
    /// evidence of leaving. Approximate location blurs the coordinate by design, so under it no fix
    /// proves leaving.
    enum CircleFixVerdict {
        case inside
        case outside
        case undecided
    }

    /// A fix dated in the future of the clock — taken before the clock was set back — cannot be
    /// placed in time, so it proves nothing either way.
    func circleVerdict(of fix: CLLocation, for geofence: Geofence) -> CircleFixVerdict {
        guard fix.horizontalAccuracy > 0, CLLocationCoordinate2DIsValid(fix.coordinate),
              fix.timestamp.timeIntervalSince(readClock().wall) <= GeofenceConstants.dwellWallClockStepTolerance
        else { return .undecided }
        let distance = fix.distance(from: CLLocation(latitude: geofence.latitude, longitude: geofence.longitude))
        if distance + fix.horizontalAccuracy <= geofence.radius { return .inside }
        guard distance - fix.horizontalAccuracy > geofence.radius,
              currentLocationAccess()?.fullAccuracy ?? true
        else { return .undecided }
        return .outside
    }

    /// A fix a resolver pass already holds — fresh, or no older than `movementFixMaxAge` — ends
    /// the visit of every registered circle it is wholly outside, as the dwell deadline's own fix
    /// does. Core Location stays the authority for the circle's ENTER and EXIT: nothing is
    /// delivered here, and an excursion it missed only stops this visit continuing across it.
    func recordOutsideEvidence(fix: CLLocation, expectedUserId: String?) async {
        guard let userId = contextStore.currentUserId, !userId.isEmpty,
              expectedUserId == nil || expectedUserId == userId
        else { return }
        let registered = await storage.getRegisteredBusinessIds()
        var judged: Set<String> = []
        for geofence in await storage.getCachedGeofences()
            where geofence.vertices == nil && tracksVisit(geofence) && registered.contains(geofence.id) {
            // The first occurrence of a duplicated id decides, as every cache lookup does.
            guard judged.insert(geofence.id).inserted,
                  circleVerdict(of: fix, for: geofence) == .outside,
                  let visit = await currentVisit(geofence: geofence, userId: userId)
            else { continue }
            await endContinuity(of: visit, geofence: geofence, observedOutsideAt: fix.timestamp)
        }
    }

    /// A fresh fix wholly outside the circle: the SDK saw the device away, so a later return must
    /// not continue this visit into a dwell spanning the absence. Core Location's exit hysteresis
    /// may mean no EXIT and no new ENTER follow, so this stay's unconfirmed dwell is lost; that is
    /// the price of never reporting one across an observed absence. No EXIT is made up: the edge
    /// was not observed. Compare-and-remove, so a visit a raced re-entry opened since survives,
    /// and a fix older than the visit says nothing about it. Ordered like an EXIT, so a late copy
    /// of the ENTER that began the visit cannot reopen it from before the absence.
    /// - Returns: whether the fix ended the visit.
    @discardableResult
    private func endContinuity(of visit: GeofenceDwellVisit, geofence: Geofence, observedOutsideAt: Date) async -> Bool {
        let exit = GeofenceExitMark(date: observedOutsideAt, processedAt: readClock())
        guard exit.overtakes(visit) else { return false }
        recordExit(exit, geofenceId: geofence.id)
        cancelEvidence(for: geofence.id, ifVisit: visit.visitId)
        await storage.removeDwellVisit(geofenceId: geofence.id, ifStill: visit.visitId)
        return true
    }

    /// After evidence was applied: stop when the visit ended or emitted, retry while it is the
    /// same visit and still pending.
    private func retryIfStillPending(geofence: Geofence, visitId: String, expectedUserId: String) async {
        guard !Task.isCancelled, contextStore.currentUserId == expectedUserId else { return }
        guard let remaining = await currentVisit(
            geofence: geofence,
            userId: expectedUserId
        ) else {
            cancelEvidence(for: geofence.id)
            return
        }
        guard !remaining.emitted else {
            cancelEvidence(for: geofence.id)
            return
        }
        // Applying the evidence can restart the candidate (a long evidence gap, or an expired old
        // visit) and schedule the new visit's own deadline. The old request must not cancel or
        // replace that new visit's task.
        if remaining.visitId == visitId {
            scheduleEvidenceRetry(for: geofence, visit: remaining)
        }
    }

    private func freshFix() async -> CLLocation? {
        if let freshFixProvider { return await freshFixProvider() }
        return await withCheckedContinuation { continuation in
            fixResolver.resolve(cached: fixResolver.latestFix, purpose: .pendingEvents) { location, isFresh in
                guard isFresh, location != nil else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: self.fixResolver.latestFix)
            }
        }
    }

    private func activeVisit(
        geofence: Geofence,
        userId: String,
        visitId: String? = nil
    ) async -> GeofenceDwellVisit? {
        guard contextStore.currentUserId == userId,
              let visit = await currentVisit(
                  geofence: geofence,
                  userId: userId
              ),
              !visit.emitted,
              visitId == nil || visit.visitId == visitId
        else { return nil }
        return visit
    }

    func scheduleEvidenceRetry(for geofence: Geofence, visit: GeofenceDwellVisit) {
        var state = evidenceRetries[geofence.id]
        if state?.visitId != visit.visitId {
            state = EvidenceRetryState(visitId: visit.visitId, attempts: 0)
        }
        guard var state, state.attempts < maxEvidenceRetryAttempts else {
            deadlineTasks.removeValue(forKey: geofence.id)?.cancel()
            return
        }
        state.attempts += 1
        evidenceRetries[geofence.id] = state
        deadlineTasks.removeValue(forKey: geofence.id)?.cancel()
        let delay = max(0, evidenceRetryDelay)
        deadlineTasks[geofence.id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1000000000))
            guard !Task.isCancelled, let self else { return }
            await self.requestQualifyingEvidence(geofenceId: geofence.id)
        }
    }

    func cancelEvidence(for geofenceId: String) {
        deadlineTasks.removeValue(forKey: geofenceId)?.cancel()
        evidenceRetries.removeValue(forKey: geofenceId)
    }

    /// Cancels only while the pending evidence is `visitId`'s: an overlapping ENTER may already have
    /// scheduled the next visit's deadline, and that one must survive the old visit's EXIT.
    func cancelEvidence(for geofenceId: String, ifVisit visitId: String) {
        guard (evidenceRetries[geofenceId]?.visitId ?? visitId) == visitId else { return }
        cancelEvidence(for: geofenceId)
    }

    func registerForegroundEvaluation() {
        #if canImport(UIKit)
        observeLifecycle(UIApplication.willEnterForegroundNotification) { coordinator in
            // First: a visit recorded in the background under foreground-only access ends here,
            // before the re-arm requests evidence for it.
            coordinator.foregroundChanged()
            Task { await coordinator.rearmPendingEvidence(includePolygons: true) }
        }
        observeLifecycle(UIApplication.didEnterBackgroundNotification) { $0.foregroundChanged() }
        observeLifecycle(UIApplication.backgroundRefreshStatusDidChangeNotification) { coordinator in
            coordinator.backgroundRefreshChanged()
        }
        #endif
    }

    private func observeLifecycle(
        _ name: Notification.Name,
        _ handle: @escaping @MainActor (GeofenceDwellCoordinator) -> Void
    ) {
        lifecycleObservers.append(notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                handle(self)
            }
        })
    }

    /// Re-arms every pending visit's deadline from its elapsed time, with a fresh retry budget.
    ///
    /// A deadline is an in-process sleep: it does not run while the app is suspended, and may run
    /// late after one. So besides foregrounding, every background wake the SDK gets — a region
    /// callback, a CLVisit — calls this, and a visit that came due while suspended requests its
    /// evidence then. That is the best iOS allows; nothing here emits on elapsed time alone.
    ///
    /// Re-arming rather than requesting now: a due visit still requests immediately, but
    /// pre-threshold evidence cannot qualify and would spend the bounded retries.
    ///
    /// - Parameter includePolygons: false on a background wake. A polygon's evidence is a forced
    ///   fresh-fix pass, and the wake's own pass is already one; a second concurrent one is
    ///   answered with the same fix, refused as an echo, and decides nothing for either.
    func rearmPendingEvidence(includePolygons: Bool) async {
        guard let userId = contextStore.currentUserId, !userId.isEmpty else { return }
        let geofences = await storage.getCachedGeofences().filter { geofence in
            geofence.dwellThresholdSeconds > 0 && (includePolygons || geofence.vertices == nil)
        }
        for geofence in geofences {
            guard let visit = await currentVisit(geofence: geofence, userId: userId), !visit.emitted,
                  // A newer visit's own deadline, scheduled while the read above was suspended,
                  // must not be replaced by this older read.
                  (evidenceRetries[geofence.id]?.visitId ?? visit.visitId) == visit.visitId
            else { continue }
            scheduleDeadline(for: geofence, visit: visit)
        }
    }
}
