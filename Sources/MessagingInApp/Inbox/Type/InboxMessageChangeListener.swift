import Foundation

/// Listener for inbox message changes.
public protocol InboxMessageChangeListener: AnyObject {
    /// Called when inbox messages have changed.
    ///
    /// - Parameter messages: The updated list of inbox messages
    func onMessagesChanged(messages: [InboxMessage])
}
