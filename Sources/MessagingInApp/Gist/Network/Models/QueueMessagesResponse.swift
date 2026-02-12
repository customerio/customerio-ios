import Foundation

/// Response model for fetching user messages from the queue (API v4).
/// Contains both in-app messages and inbox messages.
struct QueueMessagesResponse {
    let inAppMessages: [InAppMessageResponse]
    let inboxMessages: [InboxMessageResponse]

    init(inAppMessages: [InAppMessageResponse], inboxMessages: [InboxMessageResponse]) {
        self.inAppMessages = inAppMessages
        self.inboxMessages = inboxMessages
    }

    init(dictionary: [String: Any]) {
        // Parse inAppMessages array (missing/wrong keys default to empty array)
        let inAppMessagesArray = dictionary["inAppMessages"] as? [[String: Any]] ?? []
        self.inAppMessages = inAppMessagesArray.compactMap { InAppMessageResponse(dictionary: $0) }

        // Parse inboxMessages array (missing/wrong keys default to empty array)
        let inboxMessagesArray = dictionary["inboxMessages"] as? [[String: Any]] ?? []
        self.inboxMessages = inboxMessagesArray.compactMap { InboxMessageResponse(dictionary: $0) }
    }
}
