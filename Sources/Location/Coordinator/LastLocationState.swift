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

/// Loads and saves the last-location state (e.g. from Keychain).
protocol LastLocationStateStore: AnyObject {
    func load() -> LastLocationState?
    func save(_ state: LastLocationState)
}
