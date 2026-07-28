import CioInternalCommon
import Foundation

/// What `applyCachedRegistration` registered with the OS, returned so the caller can persist it
/// as the ranking-staleness reference. `nil` when registration was skipped (no user, no regions,
/// no anchor, or another sync in flight).
struct GeofenceRegistration: Equatable, Sendable {
    let center: LocationData
    let businessIds: Set<String>
}
