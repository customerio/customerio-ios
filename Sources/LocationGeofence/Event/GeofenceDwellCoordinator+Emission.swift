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
        // before the loss. So a reservation is never refused here: the stay qualified when it was
        // made, and a continuity break since — an access downgrade, say — changes nothing about it.
        if visit.dwellReservation == nil {
            guard continuityHolds(for: visit, geofenceId: geofence.id), !visit.awaitsPresenceProof else { return }
        }
        let reading = readClock()
        let elapsed = visit.timing?.elapsed(enteredAt: visit.enteredAt, until: observedAt, at: reading)
        guard let proposed = Self.qualifiedReservation(
            for: visit, observedAt: observedAt, elapsed: elapsed,
            thresholdSeconds: geofence.dwellThresholdSeconds, source: source
        ) else {
            rejectBelowThreshold(geofence: geofence, visit: visit, observedAt: observedAt, elapsed: elapsed)
            return
        }
        // A correction noted before the shapes were loaded (`pendingCorrections`), or a crossing
        // held for the polygon's evidence (`heldCoveringCrossings`), may end this stay once applied;
        // reserved now, the dwell would be a fact they cannot undo. Left to the deadline or the next
        // evidence. Judged only once the stay qualifies: evidence before the threshold schedules no
        // retry that would replace its deadline.
        if visit.dwellReservation == nil, correctionRefusesAdmission(of: visit, geofenceId: geofence.id) {
            scheduleEvidenceRetry(for: geofence, visit: visit)
            return
        }
        guard contextStore.currentUserId == userId,
              !knownExitRefusesFirstAdmission(of: visit, geofenceId: geofence.id),
              // A departure recorded but never applied, by a process that died before routing it.
              await !departureEndedStay(visit, geofence: geofence)
        else { return }
        guard dwellEmissionsInFlight.insert(visit.visitId).inserted else { return }
        defer { dwellEmissionsInFlight.remove(visit.visitId) }
        // Read before the first await. A reset during the reservation or the outbox write drops
        // this record, even when the emitter still reports the write it finished.
        let emissionToken = diagnosticToken(for: visit)
        guard let reservation = await reserve(proposed, for: visit, geofence: geofence) else { return }
        guard let delivery = await offerReservedDwell(
            reservation, geofenceId: geofence.id, visitId: visit.visitId, userId: userId
        ) else {
            await abandonReservedDwell(geofence: geofence, visit: visit)
            return
        }
        guard delivery == .persisted else { return }
        recordDiagnostic(.dwellEmitted, capturedToken: emissionToken, fenceId: geofence.id)
        await finishDwellEmission(geofence: geofence, visit: visit)
    }

    /// Evidence for a stay still too short: remembered for the short retry, and recorded with how
    /// far it fell short.
    private func rejectBelowThreshold(
        geofence: Geofence, visit: GeofenceDwellVisit, observedAt: Date, elapsed: GeofenceVisitElapsed?
    ) {
        let shortfall = elapsed.flatMap { elapsed -> TimeInterval? in
            let value = TimeInterval(geofence.dwellThresholdSeconds) - elapsed.qualifyingSeconds
            return value.isFinite && value > 0 ? value : nil
        }
        rememberEarlyEvidence(
            geofenceId: geofence.id, visitId: visit.visitId, timestamp: observedAt, shortfall: shortfall
        )
        // Continuity held on this boot with no reservation, so the stay is still too short.
        // Checked against the identity now: the caller's awaits may have spanned a sign-out.
        recordDiagnostic(
            .dwellRejected, capturedToken: diagnosticToken(for: visit),
            fenceId: geofence.id, reason: .belowThreshold, thresholdShortfall: shortfall
        )
    }

    /// How long a reserved dwell the outbox keeps refusing is offered again, by the wall clock since
    /// its evidence. After it, the delivery is given up rather than retried on every wake for good.
    static let reservedDwellLifetime: TimeInterval = 24 * 60 * 60

    /// Queues the dwell `visitId` still owes before its EXIT ends it, so an EXIT routed first does
    /// not lose a qualified DWELL. Delivered, or refused for good, it is owed no more. One the
    /// outbox could not take stays owed: removing the visit then leaves it in
    /// `GeofenceState.orphanedDwells`, offered again at launch (`deliverOrphanedDwells`).
    /// An emission already in flight for the visit owns the delivery: it is not repeated here, and
    /// if it lands after the removal it forgets the orphan the removal left.
    func flushOwedDwell(geofence: Geofence, visitId: String) async {
        guard !dwellEmissionsInFlight.contains(visitId),
              let visit = await storage.getDwellVisit(geofenceId: geofence.id), visit.visitId == visitId,
              visit.owesDwell, let reservation = visit.dwellReservation
        else { return }
        let token = diagnosticToken(for: visit)
        // Queued only: the EXIT the caller persists next must not wait on the network. The EXIT's
        // own send flushes the queue, this row first.
        guard let delivery = await offerReservedDwell(
            reservation, geofenceId: geofence.id, visitId: visitId, userId: visit.userId, queueOnly: true
        ) else {
            await abandonReservedDwell(geofence: geofence, visit: visit)
            return
        }
        guard delivery != .writeFailed else { return }
        if delivery == .persisted { recordDiagnostic(.dwellEmitted, capturedToken: token, fenceId: geofence.id) }
        _ = await storage.markDwellVisitEmitted(visit, geofenceId: geofence.id)
    }

    /// At launch, offers again each dwell a visit still owed when it was dropped
    /// (`GeofenceState.orphanedDwells`), for the user it was reserved under. Each is forgotten once
    /// delivered, refused for good, or `reservedDwellLifetime` old by the wall clock; one the outbox
    /// could not take is kept for the next launch.
    func deliverOrphanedDwells() async {
        for orphan in await storage.getOrphanedDwells() {
            let delivery = await offerReservedDwell(
                orphan.reservation, geofenceId: orphan.geofenceId, visitId: orphan.visitId, userId: orphan.userId
            )
            guard delivery != .writeFailed else { continue }
            await storage.removeOrphanedDwell(visitId: orphan.visitId)
        }
    }

    /// The one way a reserved dwell is handed to the outbox — a live visit's emission or retry, an
    /// EXIT's flush, an orphan at launch — so none skips the expiry: nil, offering nothing, once it
    /// is `reservedDwellLifetime` old, for the caller to give it up.
    /// With `queueOnly`, the dwell only reaches the outbox (`queueDwell`), before any network wait.
    private func offerReservedDwell(
        _ reservation: GeofenceDwellReservation, geofenceId: String, visitId: String, userId: String,
        queueOnly: Bool = false
    ) async -> GeofenceDwellDelivery? {
        guard !reservationExpired(reservation) else { return nil }
        let context = reservation.context(visitId: visitId)
        return queueOnly
            ? await transitionEmitter.queueDwell(
                geofenceId: geofenceId, occurredAt: reservation.occurredAt, context: context, expectedUserId: userId
            )
            : await transitionEmitter.deliverDwell(
                geofenceId: geofenceId, occurredAt: reservation.occurredAt, context: context, expectedUserId: userId
            )
    }

    /// Whether `reservation` was made `reservedDwellLifetime` or more ago on the wall clock. A clock
    /// set back reads it as younger, which only delays giving up.
    private func reservationExpired(_ reservation: GeofenceDwellReservation) -> Bool {
        readClock().wall.timeIntervalSince(reservation.occurredAt) >= Self.reservedDwellLifetime
    }

    /// Gives up a reserved dwell the outbox refused for `reservedDwellLifetime`: nothing is
    /// delivered, and the visit is marked emitted so it neither repeats the delivery nor qualifies
    /// again. A failed mark leaves it to the next attempt.
    private func abandonReservedDwell(geofence: Geofence, visit: GeofenceDwellVisit) async {
        let token = diagnosticToken(for: visit)
        guard await storage.markDwellVisitEmitted(visit, geofenceId: geofence.id) == .marked else { return }
        cancelEvidence(for: geofence.id, ifVisit: visit.visitId)
        logger.geofenceInfo("dwell_reservation_abandoned", fields: [("id", geofence.id)])
        recordDiagnostic(.dwellRejected, capturedToken: token, fenceId: geofence.id, reason: .retriesExhausted)
    }

    /// Whether a first admission of `visit` — one with no reservation yet — is refused by a native
    /// ENTER: a correction for its fence still waiting for the shapes to load
    /// (`pendingCorrections`), or a covering-circle crossing still waiting for the polygon's
    /// evidence (`heldCoveringCrossings`), either of which once applied may end the stay, or one
    /// already noted that supersedes the visit (`GeofenceEnterMarks.supersede`, as
    /// `continuityHolds` judges it). Checked on both sides of the reservation write, since either
    /// can arrive during it.
    func correctionRefusesAdmission(of visit: GeofenceDwellVisit, geofenceId: String) -> Bool {
        guard visit.dwellReservation == nil else { return false }
        return pendingCorrections.contains { $0.geofenceId == geofenceId }
            || heldCoveringCrossings[geofenceId] != nil
            || enterSuperseded(visit, geofenceId: geofenceId)
    }

    /// Whether a first admission of `visit` — one with no reservation yet — is refused because an
    /// EXIT or outside proof this process recorded ends it, though its removal has not landed, or
    /// a native EXIT callback still being routed would: the DWELL would span a departure already
    /// known. Judged at admission, not in `continuityHolds`, so the visit can still be read up to
    /// that EXIT; a callback the resolver then finds proves nothing only defers the DWELL to the
    /// next evidence. Conservative: a fix taken before the EXIT whose admission races it is lost
    /// too. A reservation already made is a fact and is never refused.
    private func knownExitRefusesFirstAdmission(of visit: GeofenceDwellVisit, geofenceId: String) -> Bool {
        visit.dwellReservation == nil
            && (exitOvertook(visit, geofenceId: geofenceId) || exitCallbackPendingOvertook(visit, geofenceId: geofenceId))
    }

    /// Reserves `proposed` on `visit`, or returns the reservation another attempt stored first; nil
    /// when nothing is to be delivered now. The admission was decided before the write; an EXIT
    /// learned during it was unknown then, so the DWELL would be a fact about the stay before it.
    /// It is withheld anyway, as extra caution: left reserved and unqueued for the EXIT's removal.
    private func reserve(
        _ proposed: GeofenceDwellReservation,
        for visit: GeofenceDwellVisit,
        geofence: Geofence
    ) async -> GeofenceDwellReservation? {
        // Rechecked at the write itself, after the awaits that led here, and once more after it:
        // a correction queued while the write was in flight is not seen by the check before it.
        // So the write only stages the reservation, which is no fact, and the admission is decided
        // after it: a refused one is taken back, and one that cannot be is left staged, delivering
        // nothing here, on a retry, or after a relaunch, which asks for fresh proof instead.
        if correctionRefusesAdmission(of: visit, geofenceId: geofence.id) {
            scheduleEvidenceRetry(for: geofence, visit: visit)
            return nil
        }
        // `visit` may be a copy read before another attempt reserved; the stored reservation wins.
        var result = await storage.stageDwellReservation(proposed, for: visit, geofenceId: geofence.id)
        if case .staged(let staged) = result {
            guard !correctionRefusesAdmission(of: visit, geofenceId: geofence.id) else {
                await storage.retractDwellReservation(staged, from: visit, geofenceId: geofence.id)
                scheduleEvidenceRetry(for: geofence, visit: visit)
                return nil
            }
            // An EXIT noted while the stage was written, still being routed: it ends this stay, and
            // its departure may precede the qualifying fix. Nothing is promoted for it to deliver.
            guard !knownExitRefusesFirstAdmission(of: visit, geofenceId: geofence.id) else {
                await storage.retractDwellReservation(staged, from: visit, geofenceId: geofence.id)
                return nil
            }
            // A recorded departure is judged in the promoting write itself (`.departed`).
            result = await storage.admitStagedDwellReservation(staged, for: visit, geofenceId: geofence.id)
        }
        switch result {
        case .reserved(let stored):
            // Reserved, the visit only repeats its delivery and needs no location, even when withheld below.
            releaseCollectionLease(geofenceId: geofence.id, ifVisit: visit.visitId)
            guard stored != proposed || !knownExitRefusesFirstAdmission(of: visit, geofenceId: geofence.id) else { return nil }
            return stored
        case .writeFailed:
            // Nothing was delivered, so nothing is lost by asking again.
            scheduleEvidenceRetry(for: geofence, visit: visit)
            return nil
        case .departed:
            await departureEndedStay(visit, geofence: geofence)
            return nil
        case .superseded, .staged:
            return nil
        }
    }

    private func finishDwellEmission(geofence: Geofence, visit: GeofenceDwellVisit) async {
        // The emitter suspends, so an EXIT and a re-entry may have replaced this visit meanwhile.
        // Writing the captured copy back would resurrect the old visit over the new one.
        switch await storage.markDwellVisitEmitted(visit, geofenceId: geofence.id) {
        case .marked:
            cancelEvidence(for: geofence.id, ifVisit: visit.visitId)
        case .writeFailed:
            scheduleEvidenceRetry(for: geofence, visit: visit)
        case .superseded:
            // Evidence scheduling now belongs to whatever visit replaced this one. A removal while
            // this was in flight left the dwell as an orphan; it is in the outbox now.
            await storage.removeOrphanedDwell(visitId: visit.visitId)
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

    /// Qualifies using the elapsed time already measured for this evidence. No wall-clock step
    /// can lengthen that time (`GeofenceVisitElapsed`).
    private static func qualifiedReservation(
        for visit: GeofenceDwellVisit,
        observedAt: Date,
        elapsed: GeofenceVisitElapsed?,
        thresholdSeconds: Int,
        source: String
    ) -> GeofenceDwellReservation? {
        // Already qualified when reserved; later evidence neither re-qualifies nor moves it.
        if let reserved = visit.dwellReservation { return reserved }
        guard let elapsed, elapsed.reaches(thresholdSeconds)
        else { return nil }
        return dwellReservation(
            for: visit, observedAt: observedAt,
            thresholdSeconds: thresholdSeconds, source: source,
            reportedSinceEntry: visit.entryObserved && elapsed.wallClockAgrees ? elapsed.sinceEntrySeconds : nil
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
        reportedSinceEntry: TimeInterval?
    ) -> GeofenceDwellReservation {
        GeofenceDwellReservation(
            occurredAtEpochMilliseconds: epochMilliseconds(observedAt),
            enteredAtEpochMilliseconds: reportedSinceEntry == nil ? nil : epochMilliseconds(visit.enteredAt),
            // From the entry to the evidence fix on the monotonic timeline, rounded up to whole
            // seconds as an EXIT's duration is, so the stay is never longer than reported (60.8 s
            // reports 61). Qualifying stays on the elapsed time it measured.
            durationSeconds: reportedSinceEntry.map { Self.wholeSecondsRoundedUp(milliseconds: Int64(($0 * 1000).rounded())) },
            thresholdSeconds: thresholdSeconds,
            detectionSource: source
        )
    }

    /// Internal for `+ExitDuration`.
    static func epochMilliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }
}
