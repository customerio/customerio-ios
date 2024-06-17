@testable import CioMessagingInApp
import Foundation

extension Message {
    convenience init(messageId: String = .random, campaignId: String = .random, pageRule: String? = nil, queueId: String? = .random) {
        var gistProperties = [
            "gist": [
                "campaignId": campaignId
            ]
        ]
        if let pageRule = pageRule {
            gistProperties["gist"]?["routeRuleApple"] = pageRule
        }

        self.init(queueId: queueId, messageId: messageId, properties: gistProperties)
    }

    static var random: Message {
        Message(messageId: .random, campaignId: .random)
    }
}
