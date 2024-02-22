import CioInternalCommon

/**
 Configuration options for push messaging module

 Example usage:
 ```
 // create a new instance
 let pushMessagingConfig = MessagingPushConfigOptions.Factory.create()
 // now, it can be modified as
 pushMessagingConfig.autoTrackPushEvents = false
 ```
 */
public struct MessagingPushConfigOptions {
    // Used to create new instance of MessagingPushConfigOptions when the MessagingPush module is configured.
    // Each property of the MessagingPushConfigOptions object can be modified by the user.
    public enum Factory {
        public static func create() -> MessagingPushConfigOptions {
            MessagingPushConfigOptions(
                writeKey: "",
                autoFetchDeviceToken: true,
                autoTrackPushEvents: true,
                showPushAppInForeground: true
            )
        }

        public static func create(with dictionary: [String: Any]) -> MessagingPushConfigOptions {
            // Each SDK config option should be able to be set from `dictionary`.
            // If one isn't provided, use current value instead.

            // Construct object with all required parameters. Each config option should be updated from `dictionary` only if available.
            let writeKey = dictionary[Keys.writeKey.rawValue] as? String
            let autoFetchDeviceToken = dictionary[Keys.autoFetchDeviceToken.rawValue] as? Bool
            let autoTrackPushEvents = dictionary[Keys.autoTrackPushEvents.rawValue] as? Bool
            let showPushAppInForeground = dictionary[Keys.showPushAppInForeground.rawValue] as? Bool

            // Use default config options as fallback
            let presetConfig = create()
            return MessagingPushConfigOptions(
                writeKey: writeKey ?? presetConfig.writeKey,
                autoFetchDeviceToken: autoFetchDeviceToken ?? presetConfig.autoFetchDeviceToken,
                autoTrackPushEvents: autoTrackPushEvents ?? presetConfig.autoTrackPushEvents,
                showPushAppInForeground: showPushAppInForeground ?? presetConfig.showPushAppInForeground
            )
        }
    }

    public enum Keys: String { // Constants used to map each of the options in MessagingPushConfigOptions
        case writeKey
        case autoFetchDeviceToken
        case autoTrackPushEvents
        case showPushAppInForeground
    }

    /// internal write key required for NotificationServiceExtension only to track metrics
    var writeKey: String
    /**
     Enable automatic fetching of device token by the SDK without the need to write custom code by the customer.
     On fetching the token, SDK will auto-register the device. This value is `true` by default.
     */
    public var autoFetchDeviceToken: Bool
    /**
     Automatic tracking of push events will automatically generate `opened` and `delivered` metrics
     for push notifications sent by Customer.io
     */
    public var autoTrackPushEvents: Bool
    /**
     Display push notifications sent by Customer.io while app is in foreground. This value is `true` by default.
     */
    public var showPushAppInForeground: Bool
}

// Add MessagingPush config options to the DIGraph like we do for SdkConfig.
// Allows dependencies to easily access module configuration via dependency injection
// in constructor.
extension DIGraphShared {
    var messagingPushConfigOptions: MessagingPushConfigOptions {
        MessagingPush.moduleConfig
    }
}
