import Foundation
import Gist

typealias GistMessage = Message

public struct InAppMessage: Equatable {
    public let messageId: String
    public let deliveryId: String? // (Currently taken from Gist's campaignId property). Can be nil when sending test
    // in-app messages

    internal init(gistMessage: GistMessage) {
        self.messageId = gistMessage.messageId
        self.deliveryId = gistMessage.gistProperties.campaignId
    }
}
