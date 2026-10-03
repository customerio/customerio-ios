import CioInternalCommon
import Foundation

extension GeofenceStorage {
    /// Closes the circle visit an observed boundary `CLMonitor` just recorded ends, in the caller's
    /// state, so the monitor's record and the visit's closure reach disk in one write: a process
    /// dying before the coordinator removes the visit leaves it closed, not open across the
    /// departure. Only for the cached circle the record's geometry is, and the visit measured
    /// against it; never a polygon's covering circle, whose EXIT proves nothing about the shape.
    /// `mark` orders the boundary against the visit as the coordinator orders its own: an EXIT
    /// must overtake it, a crossing ENTER supersede it, so a late EXIT dated before a newer visit
    /// does not close it; across a wall-clock step, processing order decides. The first closure
    /// stands. The visit is not removed: its own EXIT still reads it.
    static func closeVisit(
        in state: inout GeofenceState,
        identifier: String,
        record: MonitorRegionRecord,
        endedBy transition: GeofenceTransition,
        mark: GeofenceExitMark
    ) {
        guard var visit = state.dwellVisits?[identifier], visit.closedByObservedBoundary == nil,
              let geofence = state.cachedGeofences?.first(where: { $0.id == identifier }),
              geofence.vertices == nil, visit.geometryRevision == geofence.dwellRevision,
              let center = record.center, let radius = record.radius,
              MonitoredCircle(center: center, radius: radius, maximumRadius: .infinity).matches(geofence),
              transition == .exit ? mark.overtakes(visit) : mark.supersedes(visit)
        else { return }
        visit.closedByObservedBoundary = mark.date
        state.dwellVisits?[identifier] = visit
    }
}
