@testable import CioMessagingInApp
import Foundation

extension Message {
    convenience init(messageId: String = .random, priority: Int? = nil, campaignId: String = .random, pageRule: String? = nil, queueId: String? = .random) {
        var gistProperties = [
            "gist": [
                "campaignId": campaignId
            ]
        ]
        if let pageRule = pageRule {
            gistProperties["gist"]?["routeRuleApple"] = pageRule
        }

        self.init(messageId: messageId, queueId: queueId, priority: priority, properties: gistProperties)
    }

    static var random: Message {
        Message(messageId: .random, campaignId: .random)
    }
}
