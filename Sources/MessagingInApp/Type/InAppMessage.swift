import Foundation
import Gist

typealias GistMessage = Message

public struct InAppMessage: Equatable {
    public let instanceId: String
    public let messageId: String
    public let deliveryId: String // (Currently taken from Gist's campaignId property)

    internal init(gistMessage: GistMessage) {
        self.instanceId = gistMessage.instanceId
        self.messageId = gistMessage.messageId
        // The Gist SDK source code always populates the campaign-id. Having a nil campaignId is only common using the
        // `public init()` for Message.
        self.deliveryId = gistMessage.gistProperties.campaignId!
    }
}
