import CioInternalCommon
import Foundation

/// Builder class designed to facilitate the creation of `MessagingInAppConfigOptions`.
/// The builder pattern allows for a fluent and intuitive way to set up configuration options for
/// the module, ensuring all required and optional settings are appropriately configured before the
/// module is initialized.
///
/// **Usage Example:**
///
/// ```
/// // With a public `pk_` key, the site ID can be left out: `MessagingInAppConfigBuilder()`.
/// let config = MessagingInAppConfigBuilder(siteId: siteId)
///   // additional configuration as needed...
///   .build()
/// // Use `config` for initializing in-app module...
/// ```
public class MessagingInAppConfigBuilder {
    // configuration options for MessagingInAppConfigOptions
    private let siteId: String?
    // Only kept for the deprecated `MessagingInAppConfigOptions.region`.
    private var region: Region = .US
    private var colorScheme: ColorScheme = .auto
    private var notificationInboxAccessibilityLabels = NotificationInboxAccessibilityLabels()

    /// Initializes new `MessagingInAppConfigBuilder` without a site ID.
    /// Use when `CustomerIO` is set up with a public (`pk_`) key, which identifies the workspace.
    /// In-app uses the API key and region `CustomerIO` is set up with, so initialize `CustomerIO` first.
    public init() {
        self.siteId = nil
    }

    /// Initializes new `MessagingInAppConfigBuilder` with required configuration options.
    /// In-app uses the API key and region `CustomerIO` is set up with, so initialize `CustomerIO` first.
    /// - Parameters:
    ///   - siteId: Workspace Site ID
    public init(siteId: String) {
        self.siteId = siteId
    }

    /// Initializes new `MessagingInAppConfigBuilder` with required configuration options.
    /// - Parameters:
    ///   - siteId: Workspace Site ID
    ///   - region: Ignored, in-app uses the region `CustomerIO` is set up with.
    @available(*, deprecated, message: "region is ignored, in-app uses the region CustomerIO is set up with. Use init(siteId:).")
    public init(siteId: String, region: Region) {
        self.siteId = siteId
        self.region = region
    }

    @discardableResult
    public func setColorScheme(_ colorScheme: ColorScheme) -> MessagingInAppConfigBuilder {
        self.colorScheme = colorScheme
        return self
    }

    /// Sets the VoiceOver labels for the Visual Notification Inbox UI (bell, unread badge, loading and
    /// empty states). The SDK ships no default labels, so provide these in your app's language if you
    /// want the inbox to be announced by assistive technologies.
    /// See ``NotificationInboxAccessibilityLabels``.
    @discardableResult
    public func setNotificationInboxAccessibilityLabels(_ labels: NotificationInboxAccessibilityLabels) -> MessagingInAppConfigBuilder {
        notificationInboxAccessibilityLabels = labels
        return self
    }

    /// Builds and returns `MessagingInAppConfigOptions` instance from the configured properties.
    public func build() -> MessagingInAppConfigOptions {
        MessagingInAppConfigOptions(
            siteId: siteId ?? "",
            region: region,
            colorScheme: colorScheme,
            notificationInboxAccessibilityLabels: notificationInboxAccessibilityLabels
        )
    }
}

/// Defines errors that can occur during the `MessagingInAppConfigBuilder` building process.
public enum MessagingInAppConfigBuilderError: Error {
    case malformedConfig
    @available(*, deprecated, message: "No longer thrown, the site ID is optional when CustomerIO is set up with a public (pk_) key.")
    case missingSiteId
}

public extension MessagingInAppConfigBuilder {
    /// Constants used to map each of the options in MessagingInAppConfigOptions.
    private enum Keys: String {
        case siteId
        case notificationInboxAccessibilityLabels
    }

    /// Keys of the `notificationInboxAccessibilityLabels` sub-dictionary. `bellWithUnreadCount` is a
    /// template string carrying a `{count}` placeholder, because wrapper SDK configuration crosses a
    /// bridge that carries data but not closures.
    private enum LabelKeys: String {
        case bell
        case bellWithUnreadCount
        case loadingIndicator
        case emptyState
    }

    /// Constructs `MessagingInAppConfigOptions` by parsing and applying configurations from provided dictionary.
    /// The method is used to create `MessagingInAppConfigOptions` from wrapper SDK configurations.
    @available(iOSApplicationExtension, unavailable)
    static func build(from sdkConfig: [String: Any?]) throws -> MessagingInAppConfigOptions? {
        // If the inApp config is not present, then we assume the user does not want to use in-app messaging feature.
        guard let inAppConfig = sdkConfig["inApp"] else {
            return nil
        }
        // If the inApp config is present but it is not a dictionary, then we throw an error to indicate that the config is invalid.
        guard let config = inAppConfig as? [String: Any] else {
            throw MessagingInAppConfigBuilderError.malformedConfig
        }

        // The site ID is optional, as a public (pk_) key identifies the workspace without it.
        // Region comes from the SDK setup, so it isn't read here.
        let builder = (config[Keys.siteId.rawValue] as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
            .map { MessagingInAppConfigBuilder(siteId: $0) } ?? MessagingInAppConfigBuilder()

        if let colorSchemeStr = config["colorScheme"] as? String {
            switch colorSchemeStr {
            case "light": builder.setColorScheme(.light)
            case "dark": builder.setColorScheme(.dark)
            default: builder.setColorScheme(.auto)
            }
        }

        if let labels = config[Keys.notificationInboxAccessibilityLabels.rawValue] as? [String: Any] {
            builder.setNotificationInboxAccessibilityLabels(NotificationInboxAccessibilityLabels(
                bell: labels[LabelKeys.bell.rawValue] as? String,
                bellWithUnreadCount: (labels[LabelKeys.bellWithUnreadCount.rawValue] as? String)
                    .map(NotificationInboxAccessibilityLabels.unreadCountTemplate),
                loadingIndicator: labels[LabelKeys.loadingIndicator.rawValue] as? String,
                emptyState: labels[LabelKeys.emptyState.rawValue] as? String
            ))
        }

        return builder.build()
    }
}
