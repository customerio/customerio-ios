import Foundation

/// Dwell emission and its durable reservation, split from the coordinator's visit lifecycle so
/// both stay under the file cap. Members are `internal` rather than `private` only because of this
/// split; they remain implementation detail of an internal type.
extension GeofenceDwellCoordinator {
    /// Delivers `visit`'s dwell once the stay qualifies. The occurrence is reserved on the visit
    /// before the outbox write, and every attempt sends the reservation: a retry after a failed
    /// `emitted` write, or after a relaunch, repeats the first row — same timestamp, duration and
    /// outbox key — rather than describing the later evidence that prompted it.
    func emitDwellIfQualified(
        geofence: Geofence,
        visit: GeofenceDwellVisit,
        observedAt: Date,
        source: String,
        userId: String
    ) async {
        guard geofence.dwellThresholdSeconds > 0, !visit.emitted else { return }
        // `visit` may be a copy read before a loss its removal has not yet reached. Admission is
        // judged now; a dwell already admitted goes on to its outbox row, a fact about the stay
        // before the loss.
        guard continuityHolds(for: visit, geofenceId: geofence.id) else { return }
        guard let proposed = Self.qualifiedReservation(
            for: visit, observedAt: observedAt, at: readClock(),
            thresholdSeconds: geofence.dwellThresholdSeconds, source: source
        ) else { return }
        guard contextStore.currentUserId == userId else { return }
        guard dwellEmissionsInFlight.insert(visit.visitId).inserted else { return }
        defer { dwellEmissionsInFlight.remove(visit.visitId) }
        // `visit` may be a copy read before another attempt reserved; the stored reservation wins.
        let reservation: GeofenceDwellReservation
        switch await storage.reserveDwellEmission(proposed, for: visit, geofenceId: geofence.id) {
        case .reserved(let stored):
            reservation = stored
        case .writeFailed:
            // Nothing was delivered, so nothing is lost by asking again.
            scheduleEvidenceRetry(for: geofence, visit: visit)
            return
        case .superseded:
            return
        }
        let persisted = await transitionEmitter.trackDwell(
            geofenceId: geofence.id,
            occurredAt: reservation.occurredAt,
            context: GeofenceDwellContext(
                visitId: visit.visitId,
                enteredAt: reservation.enteredAt,
                thresholdSeconds: reservation.thresholdSeconds,
                durationSeconds: reservation.durationSeconds,
                detectionSource: reservation.detectionSource
            ),
            expectedUserId: userId
        )
        guard persisted else { return }
        await finishDwellEmission(geofence: geofence, visit: visit)
    }

    private func finishDwellEmission(geofence: Geofence, visit: GeofenceDwellVisit) async {
        // The emitter suspends, so an EXIT and a re-entry may have replaced this visit meanwhile.
        // Writing the captured copy back would resurrect the old visit over the new one.
        switch await storage.markDwellVisitEmitted(visit, geofenceId: geofence.id) {
        case .marked:
            cancelEvidence(for: geofence.id)
        case .writeFailed:
            scheduleEvidenceRetry(for: geofence, visit: visit)
        case .superseded:
            // Evidence scheduling now belongs to whatever visit replaced this one.
            break
        }
    }

    /// Repeats the dwell `visit` already reserved. Needs no new evidence: the stay qualified when
    /// the reservation was made.
    func deliverReservedDwell(geofence: Geofence, visit: GeofenceDwellVisit, userId: String) async {
        guard let reservation = visit.dwellReservation else { return }
        await emitDwellIfQualified(
            geofence: geofence, visit: visit, observedAt: reservation.occurredAt,
            source: reservation.detectionSource, userId: userId
        )
    }

    /// Qualifies on time no wall-clock step can lengthen (`GeofenceVisitElapsed`), judged as the
    /// evidence is processed at `reading`.
    private static func qualifiedReservation(
        for visit: GeofenceDwellVisit,
        observedAt: Date,
        at reading: GeofenceClockReading,
        thresholdSeconds: Int,
        source: String
    ) -> GeofenceDwellReservation? {
        // Already qualified when reserved; later evidence neither re-qualifies nor moves it.
        if let reserved = visit.dwellReservation { return reserved }
        guard let elapsed = visit.timing?.elapsed(enteredAt: visit.enteredAt, until: observedAt, at: reading),
              elapsed.reaches(thresholdSeconds)
        else { return nil }
        return dwellReservation(
            for: visit, observedAt: observedAt,
            thresholdSeconds: thresholdSeconds, source: source,
            reportsEntry: visit.entryObserved && elapsed.wallClockAgrees
        )
    }

    /// Fixes the dwell as its event will report it. A candidate's start is its first inside
    /// evidence, not an entry, so neither it nor the time since it is reported — matching Android.
    /// Nor is an entry the wall clock has since stepped away from: it is on another timeline than
    /// the dwell's own timestamp. Either still qualifies the dwell.
    private static func dwellReservation(
        for visit: GeofenceDwellVisit,
        observedAt: Date,
        thresholdSeconds: Int,
        source: String,
        reportsEntry: Bool
    ) -> GeofenceDwellReservation {
        let occurredAtMilliseconds = Self.epochMilliseconds(observedAt)
        let enteredAtMilliseconds = Self.epochMilliseconds(visit.enteredAt)
        return GeofenceDwellReservation(
            occurredAtEpochMilliseconds: occurredAtMilliseconds,
            enteredAtEpochMilliseconds: reportsEntry ? enteredAtMilliseconds : nil,
            // The difference of the two whole epoch seconds the event carries, so the three agree.
            // Can be a second more than the elapsed time qualifying used (100.9 s → 160.1 s reports
            // 60, not 59).
            durationSeconds: reportsEntry
                ? Int(max(0, occurredAtMilliseconds / 1000 - enteredAtMilliseconds / 1000))
                : nil,
            thresholdSeconds: thresholdSeconds,
            detectionSource: source
        )
    }

    private static func epochMilliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }
}
