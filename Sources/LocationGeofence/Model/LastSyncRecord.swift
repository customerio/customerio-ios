import CioInternalCommon
import Foundation

/// Snapshot of a successful server sync. Returned as an atomic pair from
/// `GeofenceStorage.getLastSync()` so callers never see a timestamp without its
/// matching location (or vice versa).
struct LastSyncRecord: Equatable, Sendable {
    let timestamp: Date
    let location: LocationData
}
