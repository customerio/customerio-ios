import CioInternalCommon
import Foundation

/// Manages inbox messages for the current user.
///
/// Inbox messages are persistent messages that users can view, mark as read/unread, and delete.
/// Messages are automatically fetched and kept in sync for identified users.
public protocol MessageInboxInstance: AutoMockable {
    /// Retrieves the current list of inbox messages.
    ///
    /// - Parameter topic: Optional topic filter. If provided, only messages with this topic in their topics list are returned. If nil, all messages are returned.
    /// - Returns: List of inbox messages for the current user, sorted by sentAt (newest first)
    func getMessages(topic: String?) async -> [InboxMessage]

    /// Registers a listener for inbox changes.
    ///
    /// The listener is immediately notified with current state, then receives all future updates.
    ///
    /// - Parameter listener: The listener to receive inbox updates
    func addChangeListener(_ listener: InboxMessageChangeListener)

    /// Unregisters a listener for inbox changes.
    ///
    /// - Parameter listener: The listener to remove
    func removeChangeListener(_ listener: InboxMessageChangeListener)

    /// Marks an inbox message as opened/read.
    /// Updates local state immediately and syncs with the server.
    ///
    /// - Parameter message: The inbox message to mark as opened
    func markMessageOpened(message: InboxMessage)

    /// Marks an inbox message as unopened/unread.
    /// Updates local state immediately and syncs with the server.
    ///
    /// - Parameter message: The inbox message to mark as unopened
    func markMessageUnopened(message: InboxMessage)

    /// Marks an inbox message as deleted.
    /// Removes the message from local state and syncs with the server.
    ///
    /// - Parameter message: The inbox message to mark as deleted
    func markMessageDeleted(message: InboxMessage)

    /// Tracks a click event for an inbox message.
    /// Sends metric event to data pipelines to track message interaction.
    ///
    /// - Parameters:
    ///   - message: The inbox message that was clicked
    ///   - actionName: Optional name of the action clicked (e.g., "view_details", "dismiss")
    func trackMessageClicked(message: InboxMessage, actionName: String?)
}
