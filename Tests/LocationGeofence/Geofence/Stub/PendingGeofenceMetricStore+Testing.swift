@testable import CioLocationGeofence
import Foundation

extension PendingGeofenceMetricStore {
    /// Rows only, for the tests that are not about the read outcome. Deliberately test-only:
    /// production callers must handle `unreadable` explicitly, which is the whole point of the
    /// enum, so a convenience that hides it does not belong in the store.
    func rows() -> [PendingGeofenceMetric] {
        guard case .rows(let rows) = read() else { return [] }
        return rows
    }
}
