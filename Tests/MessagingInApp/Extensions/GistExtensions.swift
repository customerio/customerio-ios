@testable import CioMessagingInApp
import Foundation
@testable import Gist

extension Message {
    convenience init(messageId: String, campaignId: String) {
        let gistProperties = [
            "gist": [
                "campaignId": campaignId
            ]
        ]

        self.init(messageId: messageId, properties: gistProperties)
    }

    static var random: Message {
        Message(messageId: .random, campaignId: .random)
    }
}
