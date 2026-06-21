import Foundation

/// Load state for the visual-inbox data layer, observable by the overlay UI.
///
/// Interim policy is **hidden-vs-visible** (no "error" UI outcome): the inbox renders only when
/// fully renderable, otherwise it is silently hidden. The mapping that produces this enum lives in
/// `VisualInboxRepository.computeLoadState`, so the policy stays localized there.
enum VisualInboxLoadState: Equatable {
    /// Nothing fetched yet for the current user.
    case idle
    /// A fetch is in flight.
    case loading
    /// The inbox is fully renderable: enabled, with messages, templates, and branding all
    /// available (fresh or stale). `messages` carries the selected/sorted set to render.
    case visible(messageCount: Int)
    /// The inbox is NOT renderable (disabled, or any of messages/templates/branding missing and
    /// uncached). The UI hides the inbox entirely; this is NOT an error. `reason` is for
    /// logging/diagnostics only — parity with Android's `InboxVisibility.Hidden(reason:)`.
    case hidden(reason: String)

    /// Whether the inbox should be shown by the overlay UI.
    var isInboxVisible: Bool {
        if case .visible = self { return true }
        return false
    }
}
