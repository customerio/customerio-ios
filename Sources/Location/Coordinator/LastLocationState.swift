import CioInternalCommon
import Foundation

/// State persisted for location guardrails (cached location + last synced).
struct LastLocationState: Codable, Equatable {
    var cachedLocation: LocationData?
    var lastSynced: LastSyncedRecord?
}

/// Last synced location and when it was synced.
struct LastSyncedRecord: Codable, Equatable {
    let location: LocationData
    let timestamp: Date
}

/// Loads, saves, and clears the last-location state (e.g. from file with Data Protection).
protocol LastLocationStateStore: AnyObject {
    func load() -> LastLocationState?
    func save(_ state: LastLocationState)
    func clear()
}
