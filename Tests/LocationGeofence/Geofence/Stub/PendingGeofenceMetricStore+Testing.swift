@testable import CioLocationGeofence
import Foundation

extension PendingGeofenceMetricStore {
    /// Test-only: production callers must handle `unreadable`.
    func rows() -> [PendingGeofenceMetric] {
        guard case .rows(let rows) = read() else { return [] }
        return rows
    }
}
