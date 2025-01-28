@testable import CioMessagingInApp
import Foundation

extension Message {
    convenience init(messageId: String = .random, priority: Int? = nil, campaignId: String = .random, pageRule: String? = nil, elementId: String? = nil, queueId: String? = .random) {
        var gistProperties = [
            "gist": [
                "campaignId": campaignId
            ]
        ]
        if let pageRule = pageRule {
            gistProperties["gist"]?["routeRuleApple"] = pageRule
        }
        if let elementId = elementId {
            gistProperties["gist"]?["elementId"] = elementId
        }

        self.init(messageId: messageId, queueId: queueId, priority: priority, properties: gistProperties)
    }

    static var random: Message {
        Message(messageId: .random, campaignId: .random)
    }
}
