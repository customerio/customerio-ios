import CioInternalCommon

public struct MessagingPushConfigOptions {
    public init() {
        self.autoFetchDeviceToken = true
        self.showPushAppInForeground = true
        self.autoPushClickHandling = true
    }

    /**
     Enable automatic fetching of device token by the SDK without the need to write custom code by the customer.
     On fetching the token, SDK will auto-register the device. This value is `true` by default.
     */
    public var autoFetchDeviceToken: Bool

    /**
     Display push notifications sent by Customer.io while app is in foreground. This value is `true` by default.

     Note: Has no effect if auto push click handling is disabled.
     */
    public var showPushAppInForeground: Bool

    /**
     Enable automatic push click handling by the SDK without the need to write custom code in your iOS app. This is `true` by default.
     */
    public var autoPushClickHandling: Bool
}

// Add MessagingPush config options to the DIGraph like we do for SdkConfig.
// Allows dependencies to easily access module configuration via dependency injection
// in constructor.
extension DIGraph {
    var messagingPushConfigOptions: MessagingPushConfigOptions {
        get {
            MessagingPush.shared.moduleConfig
        }
        set {
            MessagingPush.shared.moduleConfig = newValue
        }
    }
}
