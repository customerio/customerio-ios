public struct MessagingPushConfigOptions {
    // Used to create new instance of MessagingPushConfigOptions when the MessagingPushAPN module is configured.
    // Each property of the MessagingPushConfigOptions object can be modified by the user.
    public enum Factory {
        public static func create() -> MessagingPushConfigOptions {
            MessagingPushConfigOptions(
                autoFetchDeviceToken: true,
                autoTrackPushEvents: true,
                autoTrackDeviceAttributes: true
            )
        }
    }

    public enum Keys: String { // Constants used to map each of the options in MessagingPushConfigOptions
        case autoFetchDeviceToken
        case autoTrackPushEvents
        case autoTrackDeviceAttributes
    }

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
     Enable this property if you want SDK to automatic tracking of device attributes such as
     operating system, device locale, device model, app version etc
     */
    public var autoTrackDeviceAttributes: Bool
}
