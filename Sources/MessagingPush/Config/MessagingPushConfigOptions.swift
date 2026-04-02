import CioInternalCommon

/// Defines configuration options for the Customer.io Push Messaging module.
///
/// Use `MessagingPushConfigBuilder` for constructing its instances. For detailed usage, see builder class documentation.
public struct MessagingPushConfigOptions {
    public let logLevel: CioLogLevel
    public let cdpApiKey: String
    public let region: Region
    public let autoFetchDeviceToken: Bool
    public let autoTrackPushEvents: Bool
    public let showPushAppInForeground: Bool
    /// Optional App Group identifier for shared push delivery metrics storage between the host app and Notification Service Extension.
    /// When `nil`, the SDK infers the identifier from the app bundle ID using the format `group.{bundleId}.cio`.
    /// Set this when your App Group does not follow the default naming convention.
    public let appGroupId: String?
}

// Add MessagingPush config options to the DIGraph like we do for SdkConfig.
// Allows dependencies to easily access module configuration via dependency injection
// in constructor.
extension DIGraphShared {
    var messagingPushConfigOptions: MessagingPushConfigOptions {
        MessagingPush.moduleConfig
    }
}
