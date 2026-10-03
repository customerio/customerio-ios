import CioInternalCommon
import Foundation

struct LastSyncRecord: Equatable, Sendable {
    let timestamp: Date
    let location: LocationData
}
