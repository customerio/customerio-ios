import Foundation

/// Polygons: which fences are ones, whose covering-circle ENTERs are no dwell ENTER marks
/// (`polygonIds`), and the visit a pass finds left behind outside. Split from the coordinator's
/// visit lifecycle so both stay under the file cap.
extension GeofenceDwellCoordinator {
    /// Ends a polygon visit the store still holds while the polygon's membership is outside: a pass
    /// confirmed the device outside with nothing to deliver, so the EXIT that should have removed
    /// the visit was lost (the process died between the membership write and the removal). No
    /// EXIT is delivered and no mark is recorded; the visit simply cannot resume a stay the SDK saw
    /// end. A new visit a concurrent ENTER writes meanwhile is left alone.
    func endVisitLeftOutside(geofence: Geofence, expectedUserId: String?) async {
        rememberShape(of: geofence)
        guard let userId = contextStore.currentUserId, !userId.isEmpty,
              expectedUserId == nil || expectedUserId == userId,
              let visit = await storage.getDwellVisit(geofenceId: geofence.id)
        else { return }
        cancelEvidence(for: geofence.id, ifVisit: visit.visitId)
        await storage.removeDwellVisit(geofenceId: geofence.id, ifStill: visit.visitId)
    }

    /// The cache as it stands at launch; a fence seen since is remembered as it arrives.
    func loadPolygonIds() {
        Task { [weak self, storage] in
            let ids = await storage.getCachedGeofences().filter { $0.vertices != nil }.map(\.id)
            self?.rememberPolygons(ids)
        }
    }

    /// Remembers `geofence`'s shape, dropping any correction mark a polygon's covering circle left.
    func rememberShape(of geofence: Geofence) {
        if geofence.vertices != nil {
            rememberPolygons([geofence.id])
        } else {
            polygonIds.remove(geofence.id)
        }
    }

    /// A polygon's covering-circle ENTER reached the resolver: a correction its callback noted
    /// before the shape was known is withdrawn, so no evidence re-armed by that wake can end the
    /// visit. A crossing stays noted: the device left the circle, so the polygon too.
    func forgetCoveringCircleEnter(geofence: Geofence) {
        rememberShape(of: geofence)
    }

    private func rememberPolygons(_ ids: [String]) {
        for id in ids {
            polygonIds.insert(id)
            enterMarks[id]?.correction = nil
        }
    }
}
