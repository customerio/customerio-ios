import Foundation

/// Polygons: which fences are ones, whose covering-circle ENTERs are no dwell ENTER marks
/// (`polygonIds`), and the visit a pass finds left behind outside. Split from the coordinator's
/// visit lifecycle so both stay under the file cap.
extension GeofenceDwellCoordinator {
    /// Ends a polygon visit the store still holds while the polygon's membership is outside: a pass
    /// confirmed the device outside at `outsideAt` with nothing to deliver, so the EXIT that should
    /// have removed the visit was lost (the process died between the membership write and the
    /// removal). No EXIT is delivered and no mark is recorded; the visit simply cannot resume a
    /// stay the SDK saw end. Only a visit the outside fix overtakes on the monotonic timeline, as
    /// `processedAt` — the pass's own clock reading, taken before its membership write — places
    /// it, and only while the belief is still outside, judged in the removal itself: a newer
    /// inside pass may have written a new visit while this one was suspended, and that stay is
    /// its own; a wall clock since stepped back cannot keep the stranded one. An EXIT whose routing
    /// began before the removal — another pass's, suspended before it read the visit — is handed the
    /// removed visit (`rememberVisitEndedByPendingExit`), so it still names the stay it ends.
    func endVisitLeftOutside(
        geofence: Geofence,
        outsideAt: Date,
        processedAt: GeofenceClockReading? = nil,
        expectedUserId: String?
    ) async {
        let outside = GeofenceExitMark(date: outsideAt, processedAt: processedAt ?? readClock(), source: .outsideEvidence)
        guard let userId = contextStore.currentUserId, !userId.isEmpty,
              expectedUserId == nil || expectedUserId == userId,
              let removed = await storage.removeDwellVisitLeftOutside(geofenceId: geofence.id, endedBy: outside)
        else { return }
        cancelEvidence(for: geofence.id, ifVisit: removed.visitId)
        rememberVisitEndedByPendingExit(removed, geofenceId: geofence.id)
    }

    /// A refresh is about to replace the persisted catalog. Retires every catalog read still in
    /// flight (`loadPolygonIds`, `forgetCoveringCircleEnter`), so none can re-add a polygon the
    /// refresh drops; `rememberCatalog` follows once the catalog is written.
    func beginCatalogReplacement() {
        polygonCatalogGeneration &+= 1
        catalogReplacementInProgress = true
    }

    /// The catalog as a refresh just persisted it: a fence the server replaced with a circle is
    /// no longer a polygon, whatever an operation begun on the old definition learns later. Bumps
    /// the generation again, retiring reads begun since `beginCatalogReplacement` that may still
    /// have read the old catalog, and notes the corrections that waited for the shapes.
    func rememberCatalog(_ geofences: [Geofence]) {
        polygonCatalogGeneration &+= 1
        catalogReplacementInProgress = false
        polygonIds = Set(geofences.filter { $0.vertices != nil }.map(\.id))
        polygonIds.forEach(withdrawUnjudgedCrossing)
        releaseHeldCrossings(catalog: Set(geofences.map(\.id)))
        polygonIdsLoaded = true
        drainPendingCorrections()
        // The shape checks that waited for this catalog, or read the old one while it was written;
        // until none is left, so one appended during the drain runs too.
        while !pendingShapeChecks.isEmpty {
            let waiting = pendingShapeChecks
            pendingShapeChecks.removeAll()
            for geofenceId in waiting {
                taskSpawner.spawn { [weak self] in await self?.forgetCoveringCircleEnter(geofenceId: geofenceId) }
            }
        }
    }

    /// The cache as it stands at launch. Dropped if a refresh replaced the catalog meanwhile,
    /// which then holds the shapes; either way the corrections that waited are noted.
    func loadPolygonIds() {
        let generation = polygonCatalogGeneration
        taskSpawner.spawn { [weak self, storage] in
            let ids = await storage.getCachedGeofences().filter { $0.vertices != nil }.map(\.id)
            guard let self else { return }
            if self.polygonCatalogGeneration == generation {
                self.rememberPolygons(ids)
                self.polygonIdsLoaded = true
                self.drainPendingCorrections()
            }
        }
    }

    /// A polygon's covering-circle ENTER reached the resolver: a correction its callback noted
    /// before the shape was known is withdrawn, so no evidence re-armed by that wake can end the
    /// visit, and a crossing is judged by the polygon's own evidence (`judgeCoveringCrossing`). A
    /// crossing held for a fence the catalog now says is a circle is noted as that circle's. The
    /// shape is read from the persisted catalog here, never from the caller's copy. While a
    /// refresh is replacing the catalog the read waits for it (`pendingShapeChecks`), as it does
    /// again if a replacement begins during the read: an answer from a catalog on its way out
    /// proves nothing.
    func forgetCoveringCircleEnter(geofenceId: String) async {
        // Until a read spans no replacement. A replacement still in progress when the read would
        // run, or begin again, hands the check to `rememberCatalog`; one that began and ended
        // during the read is simply read past, so the check never waits for a refresh that will
        // not come.
        while true {
            guard !catalogReplacementInProgress else {
                pendingShapeChecks.append(geofenceId)
                return
            }
            let generation = polygonCatalogGeneration
            let isPolygon = await storage.isPolygon(id: geofenceId)
            guard polygonCatalogGeneration == generation else { continue }
            guard isPolygon else {
                if let unjudged = unjudgedCrossings.removeValue(forKey: geofenceId) {
                    noteEnter(unjudged, geofenceId: geofenceId, crossing: true)
                }
                if let held = heldCoveringCrossings.removeValue(forKey: geofenceId) {
                    noteEnter(held, geofenceId: geofenceId, crossing: true)
                }
                return
            }
            pendingCorrections.removeAll { $0.geofenceId == geofenceId }
            rememberPolygons([geofenceId])
            await judgeCoveringCrossing(geofenceId: geofenceId)
            return
        }
    }

    /// The crossings held for fences this catalog no longer has as polygons, whose routed ENTER will
    /// not judge them: circle routing never reads the shape. A fence now a circle has its crossing
    /// noted as that circle's; one the catalog dropped has no visit for it to end.
    private func releaseHeldCrossings(catalog: Set<String>) {
        for (geofenceId, mark) in heldCoveringCrossings where !polygonIds.contains(geofenceId) {
            heldCoveringCrossings[geofenceId] = nil
            if catalog.contains(geofenceId) { noteEnter(mark, geofenceId: geofenceId, crossing: true) }
        }
    }

    /// A polygon's held covering-circle crossing ends or restarts its visit only if the polygon was
    /// observed outside since that visit began: outside evidence for it, polygon membership or its
    /// covering circle's observed state (`GeofenceStorage.polygonDepartureEvidence`), after the
    /// visit's entry on the monotonic timeline both were recorded on
    /// (`GeofenceClockStamp.isAfterEntry`). That evidence is kept through later inside writes, so a
    /// pass that found the device back inside before this read does not hide the departure; and it
    /// is never ordered by wall date, so after the clock is set back, old evidence cannot pass for a
    /// departure from a newer visit. Evidence without a reading, or from another boot, ends nothing.
    /// Otherwise it is the OS reporting late the arrival a fix already began the visit with, and is
    /// dropped, leaving the visit, its id, entry and timing untouched; the polygon's own passes still
    /// end the stay.
    func judgeCoveringCrossing(geofenceId: String) async {
        guard let crossing = heldCoveringCrossings[geofenceId] else { return }
        let evidence = await storage.polygonDepartureEvidence(geofenceId: geofenceId)
        // A later crossing held during the read waits for its own routed ENTER.
        if heldCoveringCrossings[geofenceId] == crossing { heldCoveringCrossings[geofenceId] = nil }
        guard let visit = evidence.visit, evidence.outside.contains(where: { $0.isAfterEntry(of: visit) }) else { return }
        noteEnter(crossing, geofenceId: geofenceId, crossing: true)
    }

    /// Ends `visit` when its polygon was left after it began, by evidence on disk that nothing
    /// applied: its whole covering circle's observed EXIT, or an outside membership proof, recorded
    /// after its entry on the monotonic timeline (`GeofenceStorage.polygonDepartureEvidence`). A
    /// process that dies between recording either and ending the stay leaves the visit open, and
    /// the EXIT is never routed again; after a short return, fresh proof would then qualify a dwell
    /// across the absence. Checked before a stay is resumed or first admitted. A reserved dwell is a
    /// fact about the stay before the departure and is left to deliver. Compare-and-remove, so a
    /// visit written since survives.
    /// - Returns: whether the visit was ended.
    @discardableResult
    func departureEndedStay(_ visit: GeofenceDwellVisit, geofence: Geofence) async -> Bool {
        guard geofence.vertices != nil, visit.dwellReservation == nil else { return false }
        let evidence = await storage.polygonDepartureEvidence(geofenceId: geofence.id, wholeCircleOnly: true)
        guard let stored = evidence.visit, stored.visitId == visit.visitId,
              evidence.outside.contains(where: { $0.isAfterEntry(of: stored) })
        else { return false }
        cancelEvidence(for: geofence.id, ifVisit: visit.visitId)
        await storage.removeDwellVisit(geofenceId: geofence.id, ifStill: visit.visitId)
        return true
    }

    /// Notes the corrections and crossings that arrived before the shapes were known, for the fences
    /// the catalog now says are circles; a polygon's covering-circle correction is dropped
    /// (`polygonIds`).
    private func drainPendingCorrections() {
        // The polygons' crossings were withdrawn and held by `rememberPolygons`; the rest are
        // circles', noted now.
        for (geofenceId, mark) in unjudgedCrossings where !polygonIds.contains(geofenceId) {
            noteEnter(mark, geofenceId: geofenceId, crossing: true)
        }
        unjudgedCrossings.removeAll()
        let waiting = pendingCorrections
        pendingCorrections.removeAll()
        for (geofenceId, mark) in waiting where !polygonIds.contains(geofenceId) {
            noteEnter(mark, geofenceId: geofenceId, crossing: false)
        }
    }

    private func rememberPolygons(_ ids: [String]) {
        for id in ids {
            polygonIds.insert(id)
            enterMarks[id]?.correction = nil
            withdrawUnjudgedCrossing(id)
        }
    }

    /// A crossing seen before the shapes were known, for a fence now known to be a polygon: held
    /// for the routed ENTER to judge.
    private func withdrawUnjudgedCrossing(_ geofenceId: String) {
        guard let unjudged = unjudgedCrossings.removeValue(forKey: geofenceId) else { return }
        holdCoveringCrossing(unjudged, geofenceId: geofenceId)
    }
}
