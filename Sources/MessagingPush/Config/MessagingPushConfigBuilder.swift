import CioInternalCommon
import Foundation

/// Builder class designed to facilitate the creation of `MessagingPushConfigOptions`.
/// The builder pattern allows for a fluent and intuitive way to set up configuration options for
/// the module, ensuring all required and optional settings are appropriately configured before the
/// module is initialized.
///
/// **Usage Example:**
///
/// When calling from application
///
/// ```
/// let config = MessagingPushConfigBuilder()
///   .autoTrackPushEvents(true)
///   // additional configuration as needed...
///   .build()
/// // Use `config` for initializing push module in AppDelegate...
/// ```
///
/// When calling from application extension
///
/// ```
/// let config = MessagingPushConfigBuilder(cdpApiKey: "your_cdp_api_key")
///   .autoTrackPushEvents(true)
///   // additional configuration as needed...
///   .build()
/// // Use `config` for initializing the push module in NotificationServiceExtension...
/// ```
public class MessagingPushConfigBuilder {
    // configuration options for SdkConfig
    private var logLevel: CioLogLevel = .error

    // configuration options for MessagingPushConfigOptions
    private let cdpApiKey: String
    private var autoFetchDeviceToken: Bool = true
    private var autoTrackPushEvents: Bool = true
    private var showPushAppInForeground: Bool = true

    // Need to be available for NotificationServiceExtension and AppDelegate
    // otherwise, it will throw an error when we add this module in the NotificationServiceExtension target in podfile
    public init() {
        self.cdpApiKey = ""
    }

    @available(iOS, unavailable)
    @available(visionOS, unavailable)
    @available(iOSApplicationExtension, introduced: 13.0)
    @available(visionOSApplicationExtension, introduced: 1.0)
    /// Initializes new `MessagingPushConfigBuilder` with required configuration options.
    /// - Parameters:
    ///   - cdpApiKey: Customer.io Data Pipeline API Key required for NotificationServiceExtension only to track metrics
    public init(cdpApiKey: String) {
        self.cdpApiKey = cdpApiKey
    }

    /// Configures the log level for NotificationServiceExtension, allowing customization of SDK log
    /// verbosity to help setup and debugging
    @discardableResult
    @available(iOS, unavailable)
    @available(visionOS, unavailable)
    @available(iOSApplicationExtension, introduced: 13.0)
    @available(visionOSApplicationExtension, introduced: 1.0)
    public func logLevel(_ logLevel: CioLogLevel) -> MessagingPushConfigBuilder {
        self.logLevel = logLevel
        return self
    }

    /// Enable automatic fetching of device token by the SDK without the need to write custom code by the customer.
    /// On fetching the token, SDK will auto-register the device. This value is `true` by default.
    @discardableResult
    public func autoFetchDeviceToken(_ value: Bool) -> MessagingPushConfigBuilder {
        autoFetchDeviceToken = value
        return self
    }

    /// Automatic tracking of push events will automatically generate `opened` and `delivered` metrics for
    /// push notifications sent by Customer.io. This value is `true` by default.
    @discardableResult
    public func autoTrackPushEvents(_ value: Bool) -> MessagingPushConfigBuilder {
        autoTrackPushEvents = value
        return self
    }

    /// Display push notifications sent by Customer.io while app is in foreground. This value is `true` by default.
    @discardableResult
    public func showPushAppInForeground(_ value: Bool) -> MessagingPushConfigBuilder {
        showPushAppInForeground = value
        return self
    }

    /// Builds and returns `MessagingPushConfigOptions` instance from the configured properties.
    public func build() -> MessagingPushConfigOptions {
        let configOptions = MessagingPushConfigOptions(
            logLevel: logLevel,
            cdpApiKey: cdpApiKey,
            autoFetchDeviceToken: autoFetchDeviceToken,
            autoTrackPushEvents: autoTrackPushEvents,
            showPushAppInForeground: showPushAppInForeground
        )

        return configOptions
    }
}

public extension MessagingPushConfigBuilder {
    /// Constants used to map each of the options in MessagingPushConfigOptions.
    enum Keys: String {
        case autoFetchDeviceToken
        case autoTrackPushEvents
        case showPushAppInForeground
    }

    /// Constructs `MessagingPushConfigOptions` by parsing and applying configurations from provided dictionary.
    @available(iOSApplicationExtension, unavailable)
    static func build(from dictionary: [String: Any]) -> MessagingPushConfigOptions {
        let builder = MessagingPushConfigBuilder()

        if let autoFetchDeviceToken = dictionary[Keys.autoFetchDeviceToken.rawValue] as? Bool {
            builder.autoFetchDeviceToken(autoFetchDeviceToken)
        }
        if let autoTrackPushEvents = dictionary[Keys.autoTrackPushEvents.rawValue] as? Bool {
            builder.autoTrackPushEvents(autoTrackPushEvents)
        }
        if let showPushAppInForeground = dictionary[Keys.showPushAppInForeground.rawValue] as? Bool {
            builder.showPushAppInForeground(showPushAppInForeground)
        }

        return builder.build()
    }
}
