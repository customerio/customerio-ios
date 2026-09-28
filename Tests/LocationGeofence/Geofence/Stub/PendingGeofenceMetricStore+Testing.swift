@testable import CioLocationGeofence
import Foundation

extension PendingGeofenceMetricStore {
    /// Rows only, for tests that are not about the read outcome. Test-only because production
    /// callers must handle `unreadable` explicitly.
    func rows() -> [PendingGeofenceMetric] {
        guard case .rows(let rows) = read() else { return [] }
        return rows
    }
}
