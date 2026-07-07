import CioInternalCommon
import Foundation

/// Listener for actions taken on Visual Notification Inbox messages.
///
/// Mirrors ``InAppEventListener`` (used for in-app messages) but for the inbox overlay. Register it
/// via `MessagingInApp.shared.setInboxEventListener(_:)` to be notified when the user taps a message
/// action and, optionally, to intercept that action so the SDK does NOT run its default behavior.
///
/// "Default behavior" is the SDK opening the action's url itself (`http(s)`/`openUrl`/`newTab`) or
/// logging an unhandled `deeplink`. Returning `true` from ``messageActionTaken(message:actionName:actionValue:)``
/// tells the SDK the host fully handled the action (e.g. it navigated in-app), so the SDK suppresses
/// its default. Returning `false` (or not setting a listener) lets the SDK run the default.
///
/// Dismiss is unaffected: tapping a message whose action resolves to a dismiss always removes it and
/// is never routed to this listener.
public protocol InboxEventListener: AutoMockable {
    /// Called when a non-dismiss action is taken on an inbox message.
    ///
    /// - Parameters:
    ///   - message: The inbox message the action was taken on.
    ///   - actionName: The Jist action name (e.g. `messageAction`).
    ///   - actionValue: The action's resolved value — typically the destination url (the message's
    ///     `properties[actionName].url`). Empty string if the action carried no value.
    /// - Returns: `true` if the host fully handled the action and the SDK should suppress its default
    ///   navigation; `false` to let the SDK run its default behavior.
    func messageActionTaken(message: InboxMessage, actionName: String, actionValue: String) -> Bool

    /// Called when an inbox message is first shown to the user (rendered in the visible panel/list).
    ///
    /// Fired once per message per render session (deduped by the SDK) — not on every recompose. This
    /// is an observe-only callback; its return value has no effect on SDK behavior.
    /// - Parameter message: The inbox message that became visible.
    func messageShown(message: InboxMessage)

    /// Called when an inbox message is opened (the SDK marks it opened — e.g. when the panel opens and
    /// its messages are auto-marked, deduped by the SDK so it never fires twice for the same message).
    ///
    /// Observe-only; its return value has no effect on SDK behavior.
    /// - Parameter message: The inbox message that was opened.
    func messageOpened(message: InboxMessage)

    /// Called when an inbox message is dismissed (removed) — e.g. the web-parity tap-to-dismiss.
    ///
    /// Observe-only; its return value has no effect on SDK behavior.
    /// - Parameter message: The inbox message that was dismissed.
    func messageDismissed(message: InboxMessage)
}

// MARK: - Default implementations (source compatibility)

public extension InboxEventListener {
    /// Default no-op so adding these observe callbacks stays source-compatible with existing listeners.
    func messageShown(message: InboxMessage) {}
    /// Default no-op so adding these observe callbacks stays source-compatible with existing listeners.
    func messageOpened(message: InboxMessage) {}
    /// Default no-op so adding these observe callbacks stays source-compatible with existing listeners.
    func messageDismissed(message: InboxMessage) {}
}
