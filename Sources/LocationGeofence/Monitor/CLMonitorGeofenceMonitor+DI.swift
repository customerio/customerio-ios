import CioInternalCommon
import Foundation

@available(iOS 17.0, *)
extension CLMonitorGeofenceMonitor {
    /// Process-wide singleton, same lifetime rationale as `CoreLocationGeofenceMonitor.shared`.
    @MainActor
    static let shared = CLMonitorGeofenceMonitor(
        logger: DIGraphShared.shared.logger,
        storage: DIGraphShared.shared.geofenceStorage
    )
}
