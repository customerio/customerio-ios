import Foundation

typealias GistMessage = Message

public struct InAppMessage: Equatable {
    public let messageId: String
    public let deliveryId: String? // (Currently taken from Gist's campaignId property). Can be nil when sending test
    // in-app messages

    init(gistMessage: GistMessage) {
        // Internally, the SDK refers to the message ID as "templateId".
        // To keep backwards compatibility, map Message.templateId to "messageId".
        self.messageId = gistMessage.messageId
        self.deliveryId = gistMessage.gistProperties.campaignId
    }
}
