import Foundation

/// Listener for notification inbox message changes.
///
/// Receives real time notifications when inbox messages are added, updated, or removed.
/// Callbacks are executed on the main thread, making it safe to update UI directly.
///
/// **Important:** Call `NotificationInbox.removeChangeListener(_:)` when done (e.g., in `viewDidDisappear` or `deinit`)
/// to stop receiving updates and avoid unnecessary work.
@MainActor
public protocol NotificationInboxChangeListener: AnyObject {
    /// Called when inbox messages change.
    ///
    /// Invoked immediately with current messages when registered, then again whenever
    /// messages are added, updated, or removed.
    ///
    /// - Parameter messages: Current inbox messages, filtered by topic if specified during registration,
    ///   sorted by sentAt (newest first)
    func onMessagesChanged(messages: [InboxMessage])
}
