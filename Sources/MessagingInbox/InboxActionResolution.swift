import Foundation

/// A resolved, non-dismiss inbox action mapped from a Jist `onAction` event into the fields the
/// overlay needs for default navigation (item 12) and the host listener (item 13). Dismiss is
/// resolved separately (and never reaches here).
///
/// Mirrors the web SDK's `InboxActionConfig` (gist-web `inbox-component-manager.handleInboxAction`):
/// `{ behavior, action, name, dismiss, newTab }`. `newTab` is web-only (open in a new browser tab)
/// and is not modeled here — native always opens externally.
@available(iOS 13.0, *)
struct InboxActionResolution: Equatable {
    /// The action `behavior` from the message's `properties[actionName]`. Matches the web enum
    /// `InboxActionBehavior` (minus `dismiss`, which is resolved before this type is built).
    enum Behavior: Equatable {
        /// Open `actionValue` as a URL.
        case openUrl
        /// Open `actionValue` as a deep link. Web treats this identically to `openUrl`; on iOS both
        /// go through `UIApplication.open`, which routes http(s) to the browser and a custom scheme
        /// to the registered/host app.
        case openDeeplink
        /// A host-custom action: the SDK performs no navigation, it only offers the action to the host
        /// listener (web dispatches its `inboxMessageAction` event and does nothing else).
        case performAction
        /// Unrecognized / absent behavior — host-only no-op.
        case unknown
    }

    /// The action's `name` (tracking name), falling back to the Jist node name when absent.
    let actionName: String
    /// The action's destination/value (`action`): a URL for `openUrl`/`openDeeplink`, or a custom
    /// value for `performAction`. Never force-unwrapped downstream.
    let actionValue: String?
    /// The resolved action behavior.
    let behavior: Behavior
    /// "Auto dismiss on click": `data.dismiss == true` — the message should be removed after its
    /// (non-dismiss) action runs. Web parity: `dismiss` chains onto any behavior.
    let dismiss: Bool
}
