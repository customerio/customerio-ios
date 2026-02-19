import CioInternalCommon
import Foundation

/// Manages inbox messages for the current user.
///
/// Inbox messages are persistent messages that users can view, mark as read/unread, and delete.
/// Messages are automatically fetched and kept in sync for identified users.
public protocol NotificationInbox {
    /// Retrieves the current list of inbox messages.
    ///
    /// - Parameter topic: Optional topic filter. If provided, only messages with this topic in their topics list are returned. If nil, all messages are returned.
    /// - Returns: List of inbox messages for the current user, sorted by sentAt (newest first)
    func getMessages(topic: String?) async -> [InboxMessage]

    /// Registers a listener for inbox changes.
    ///
    /// The listener is immediately notified with current state, then receives all future updates.
    /// Callbacks are executed on the main thread.
    ///
    /// **Important:** Must be called from the main thread. Call `removeChangeListener(_:)` when done
    /// (typically in `viewDidDisappear` or `deinit`) to stop receiving updates and avoid unnecessary work.
    ///
    /// - Parameters:
    ///   - listener: The listener to receive inbox updates
    ///   - topic: Optional topic filter. If provided, only messages with this topic are sent to the listener.
    ///            If nil, all messages are sent. Topic matching is case-insensitive.
    @MainActor
    func addChangeListener(_ listener: NotificationInboxChangeListener, topic: String?)

    /// Unregisters a listener for inbox changes.
    ///
    /// Removes all registrations of the listener, regardless of topic filters.
    /// Can be called from any thread, including from `deinit`.
    ///
    /// **Note:** Removal is scheduled asynchronously on the main thread and may not complete immediately.
    /// The listener may still receive callbacks until removal completes if the listener object remains alive.
    ///
    /// - Parameter listener: The listener to remove
    func removeChangeListener(_ listener: NotificationInboxChangeListener)

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

// MARK: - Protocol Extension for Default Parameters

public extension NotificationInbox {
    /// Retrieves all inbox messages without topic filter.
    ///
    /// - Returns: List of all inbox messages for the current user, sorted by sentAt (newest first)
    func getMessages() async -> [InboxMessage] {
        await getMessages(topic: nil)
    }

    /// Registers a listener for all inbox changes without topic filter.
    ///
    /// The listener is immediately notified with current state, then receives all future updates.
    /// Callbacks are executed on the main thread.
    ///
    /// **Important:** Must be called from the main thread. Call `removeChangeListener(_:)` when done
    /// (typically in `viewDidDisappear` or `deinit`) to stop receiving updates and avoid unnecessary work.
    ///
    /// - Parameter listener: The listener to receive inbox updates
    @MainActor
    func addChangeListener(_ listener: NotificationInboxChangeListener) {
        addChangeListener(listener, topic: nil)
    }

    /// Tracks a click event for an inbox message without an action name.
    /// Sends metric event to data pipelines to track message interaction.
    ///
    /// - Parameter message: The inbox message that was clicked
    func trackMessageClicked(message: InboxMessage) {
        trackMessageClicked(message: message, actionName: nil)
    }
}
