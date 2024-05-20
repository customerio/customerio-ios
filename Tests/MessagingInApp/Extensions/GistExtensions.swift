@testable import CioMessagingInApp
import Foundation

extension Message {
    convenience init(messageId: String, campaignId: String, queueId: String = .random, elementId: String? = nil) {
        var gistProperties = [
            "campaignId": campaignId
        ]

        if let elementId = elementId {
            gistProperties["elementId"] = elementId
        }

        self.init(queueId: queueId, messageId: messageId, properties: [
            "gist": gistProperties
        ])
    }

    static var random: Message {
        Message(messageId: .random, campaignId: .random)
    }

    static var randomInline: Message {
        Message(messageId: .random, campaignId: .random, elementId: .random)
    }
}
