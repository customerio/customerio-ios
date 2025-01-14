import CioInternalCommon
import Foundation

/*
 EventBus events that are specific to the in-app SDK.
 */

/// When in-app SDK has fetched in-app messages from the server.
public struct InAppMessagesFetchedEvent: EventRepresentable {
    public let storageId: String
    public let params: [String: String]
    public let timestamp: Date

    public init(storageId: String = UUID().uuidString, timestamp: Date = Date(), params: [String: String] = [:]) {
        self.storageId = storageId
        self.timestamp = timestamp
        self.params = params
    }
}
