import CioInternalCommon
import Foundation

@available(iOS 17.0, *)
extension CLMonitorGeofenceMonitor {
    /// Process-wide singleton: a second `CLMonitor` with the same name throws.
    @MainActor
    static let shared = CLMonitorGeofenceMonitor(
        logger: DIGraphShared.shared.logger,
        storage: DIGraphShared.shared.geofenceStorage
    )
}
