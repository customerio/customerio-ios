import Foundation

/// Polygons: which fences are ones, whose covering-circle ENTERs are no dwell ENTER marks
/// (`polygonIds`). Split from the coordinator's visit lifecycle so both stay under the file cap.
extension GeofenceDwellCoordinator {
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
