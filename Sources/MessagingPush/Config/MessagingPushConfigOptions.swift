import CioInternalCommon

/// Defines configuration options for the Customer.io Push Messaging module.
///
/// Use `MessagingPushConfigBuilder` for constructing its instances. For detailed usage, see builder class documentation.
public struct MessagingPushConfigOptions {
    public let logLevel: CioLogLevel
    public let cdpApiKey: String
    public let autoFetchDeviceToken: Bool
    public let autoTrackPushEvents: Bool
    public let showPushAppInForeground: Bool
}

// Add MessagingPush config options to the DIGraph like we do for SdkConfig.
// Allows dependencies to easily access module configuration via dependency injection
// in constructor.
extension DIGraphShared {
    var messagingPushConfigOptions: MessagingPushConfigOptions {
        MessagingPush.moduleConfig
    }
}
