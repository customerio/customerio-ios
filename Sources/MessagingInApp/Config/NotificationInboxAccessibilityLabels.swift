import Foundation

/// Host-provided accessibility (VoiceOver) labels for the Visual Notification Inbox UI —
/// ``NotificationInboxView``, ``NotificationInboxBell`` and ``NotificationInboxOverlay``.
///
/// The SDK ships **no** text of its own in the visual inbox: the empty state is an icon and the loading
/// state is the system spinner, so nothing on screen needs translating. Accessibility labels are the
/// one place a string is still needed, and because the SDK cannot know the host app's language, every
/// label is optional and **nil by default**. A nil label emits no accessibility label for that element:
/// the empty-state icon is hidden from VoiceOver, the loading spinner is not focusable, and the bell
/// stays focusable and tappable but unnamed (hiding it would leave VoiceOver users no way into the
/// inbox). Provide values in whatever language your app ships in — typically from your own
/// `Localizable.strings`.
///
/// ## Usage
/// ```swift
/// MessagingInAppConfigBuilder(siteId: siteId, region: .US)
///     .setNotificationInboxAccessibilityLabels(NotificationInboxAccessibilityLabels(
///         bell: NSLocalizedString("inbox.bell", comment: ""),
///         bellWithUnreadCount: { count in
///             String.localizedStringWithFormat(NSLocalizedString("inbox.unread_count", comment: ""), count)
///         },
///         loadingIndicator: NSLocalizedString("inbox.loading", comment: ""),
///         emptyState: NSLocalizedString("inbox.empty", comment: "")
///     ))
///     .build()
/// ```
///
/// Threading: `bellWithUnreadCount` is invoked on the main thread while the bell renders, each time the
/// unread count changes. Keep it cheap and side-effect free.
public struct NotificationInboxAccessibilityLabels {
    /// Label for the inbox bell button. Also used when the bell shows an unread badge but
    /// `bellWithUnreadCount` is not provided. nil → the bell is announced as an unnamed button.
    public let bell: String?

    /// Builds the bell's label when it shows an unread badge, given the unread count. A closure (not a
    /// template) so hosts can apply their language's plural rules. nil → falls back to `bell`.
    ///
    /// The badge itself is always hidden from VoiceOver, so the count is announced only through this
    /// label — never as bare digits appended to the button.
    public let bellWithUnreadCount: ((Int) -> String)?

    /// Label announced for the loading spinner. nil → the spinner is not an accessibility element.
    public let loadingIndicator: String?

    /// Label announced for the empty-state icon. nil → the icon is hidden from assistive technologies.
    public let emptyState: String?

    public init(
        bell: String? = nil,
        bellWithUnreadCount: ((Int) -> String)? = nil,
        loadingIndicator: String? = nil,
        emptyState: String? = nil
    ) {
        self.bell = bell
        self.bellWithUnreadCount = bellWithUnreadCount
        self.loadingIndicator = loadingIndicator
        self.emptyState = emptyState
    }

    /// Placeholder replaced by the unread count in ``unreadCountTemplate(_:)``.
    ///
    /// Internal: it exists only for the wrapper SDKs, whose configuration crosses a bridge that carries
    /// data but not closures. Native hosts pass a closure and never need this.
    static let countPlaceholder = "{count}"

    /// Builds a `bellWithUnreadCount` closure from a template string containing ``countPlaceholder``,
    /// e.g. `"{count} unread notifications"`. Used by the wrapper-configuration path in
    /// ``MessagingInAppConfigBuilder/build(from:)``; a template without the placeholder is returned
    /// verbatim for every count.
    static func unreadCountTemplate(_ template: String) -> (Int) -> String {
        { count in template.replacingOccurrences(of: countPlaceholder, with: String(count)) }
    }
}
