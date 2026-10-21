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
    /// its own; a wall clock since stepped back cannot keep the stranded one.
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
        cancelEvidence(for: geofence.id, ifVisit: removed)
    }

    /// A refresh is about to replace the persisted catalog. Retires every catalog read still in
    /// flight (`loadPolygonIds`, `forgetCoveringCircleEnter`), so none can re-add a polygon the
    /// refresh drops; `rememberCatalog` follows once the catalog is written.
    func beginCatalogReplacement() {
        polygonCatalogGeneration &+= 1
    }

    /// The catalog as a refresh just persisted it: a fence the server replaced with a circle is
    /// no longer a polygon, whatever an operation begun on the old definition learns later. Bumps
    /// the generation again, retiring reads begun since `beginCatalogReplacement` that may still
    /// have read the old catalog, and notes the corrections that waited for the shapes.
    func rememberCatalog(_ geofences: [Geofence]) {
        polygonCatalogGeneration &+= 1
        polygonIds = Set(geofences.filter { $0.vertices != nil }.map(\.id))
        polygonIdsLoaded = true
        drainPendingCorrections()
    }

    /// The cache as it stands at launch. Dropped if a refresh replaced the catalog meanwhile,
    /// which then holds the shapes; either way the corrections that waited are noted.
    func loadPolygonIds() {
        let generation = polygonCatalogGeneration
        Task { [weak self, storage] in
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
    /// visit. A crossing stays noted: the device left the circle, so the polygon too. The shape is
    /// read from the persisted catalog here, never from the caller's copy, and the answer is
    /// dropped if a refresh replaced the catalog while it was read.
    func forgetCoveringCircleEnter(geofenceId: String) async {
        let generation = polygonCatalogGeneration
        guard await storage.isPolygon(id: geofenceId), polygonCatalogGeneration == generation else { return }
        pendingCorrections.removeAll { $0.geofenceId == geofenceId }
        rememberPolygons([geofenceId])
    }

    /// Notes the corrections that arrived before the shapes were known, for the fences the catalog
    /// now says are circles; a polygon's covering-circle correction is dropped (`polygonIds`).
    private func drainPendingCorrections() {
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
        }
    }
}
