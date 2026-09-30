import CioInternalCommon
import Foundation

/// Returned so the caller can persist it as the ranking-staleness reference.
struct GeofenceRegistration: Equatable, Sendable {
    let center: LocationData
    let businessIds: Set<String>
}
