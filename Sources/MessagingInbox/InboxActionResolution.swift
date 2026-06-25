import Foundation

/// A resolved, non-dismiss inbox action mapped from a Jist `onAction` event into the fields the
/// overlay needs for default navigation (item 12) and the host listener (item 13). Dismiss is
/// resolved separately (and never reaches here).
@available(iOS 13.0, *)
struct InboxActionResolution: Equatable {
    /// The action `behavior` from the message's `properties[actionName]` (e.g. `openUrl`, `deeplink`,
    /// `newTab`). `none` when the message carried no behavior — we then infer from the url scheme.
    enum Behavior: Equatable {
        case openUrl
        case newTab
        case deeplink
        case none
    }

    /// The Jist action name (e.g. `messageAction`).
    let actionName: String
    /// The destination url, if any. Never force-unwrapped downstream.
    let url: String?
    /// The resolved action behavior.
    let behavior: Behavior
    /// "Auto dismiss on click": `data.dismiss == true` — the message should be removed after its
    /// (non-dismiss) action runs.
    let dismiss: Bool
}
