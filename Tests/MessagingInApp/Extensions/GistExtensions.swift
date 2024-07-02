@testable import CioMessagingInApp
import Foundation

extension Message {
    convenience init(messageId: String = .random, campaignId: String = .random, pageRule: String? = nil, queueId: String? = .random, elementId: String? = nil, priority: Int? = nil) {
        var gistProperties = [
            "campaignId": campaignId
        ]

        if let elementId = elementId {
            gistProperties["elementId"] = elementId
        }
        if let pageRule = pageRule {
            gistProperties["routeRuleApple"] = pageRule
        }

        self.init(queueId: queueId, priority: priority, messageId: messageId, properties: [
            "gist": gistProperties
        ])
    }

    static var random: Message {
        Message(elementId: nil)
    }

    static var randomInline: Message {
        Message(elementId: .random)
    }
}
