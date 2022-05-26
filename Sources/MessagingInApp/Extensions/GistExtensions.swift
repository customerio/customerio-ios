import Foundation
import Gist

internal extension Message {
    // Used for getting details about the Message object for sending to logs.
    var describeForLogs: String {
        "id: \(messageId), queueId: \(queueId ?? "none"), campaignId: \(gistProperties.campaignId ?? "none")"
    }
}
