import Foundation

/// A resolved, non-dismiss inbox action mapped from a Jist `onAction` event into the fields the
/// overlay needs for default navigation (item 12) and the host listener (item 13). Dismiss is
/// resolved separately (and never reaches here).
///
/// Mirrors the web SDK's `InboxActionConfig` (gist-web `inbox-component-manager.handleInboxAction`):
/// `{ behavior, action, name, dismiss, newTab }`. `newTab` is web-only (open in a new browser tab)
/// and is not modeled here — native always opens externally.
struct InboxActionResolution: Equatable {
    /// The action `behavior` from the message's `properties[actionName]`. Matches the web enum
    /// `InboxActionBehavior` (minus `dismiss`, which is resolved before this type is built).
    enum Behavior: Equatable {
        /// Open `actionValue` externally via `UIApplication.open`, as the platform resolves it.
        case openUrl
        /// Route `actionValue` through the SDK's shared deep-link handling
        /// (`deepLinkUtil.handleDeepLink`: host `deepLinkCallback` → universal-link handoff → system
        /// open) — identical to push-notification and in-app-message deep links, so inbox deep links
        /// behave consistently with the rest of the SDK (distinct from `openUrl`'s plain external open).
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
