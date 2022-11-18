import Foundation

/**
 Configuration options for the Customer.io SDK.
 See `CustomerIO.config()` to configurate the SDK.
 */
public struct SdkConfig {
    // Used to create new instance of SdkConfig when the SDK is initialized.
    // Then, each property of the SdkConfig object can be modified by the user.
    public enum Factory {
        public static func create(region: Region) -> SdkConfig {
            SdkConfig(trackingApiUrl: region.productionTrackingUrl)
        }
    }

    /**
     Base URL to use for the Customer.io track API. You will more then likely not modify this value.

     If you override this value, `Region` set when initializing the SDK will be ignored.
     */
    public var trackingApiUrl: String

    /**
     Automatic tracking of push events will automatically generate `opened` and `delivered` metrics
     for push notifications sent by Customer.io
     */
    public var autoTrackPushEvents: Bool = true

    /**
     Number of tasks in the background queue before the queue begins operating.
     This is mostly used during development to test configuration is setup. We do not recommend
     modifying this value because it impacts battery life of mobile device.
     */
    public var backgroundQueueMinNumberOfTasks = 10

    /// The number of seconds to delay running queue after a task has been added to it.
    public var backgroundQueueSecondsDelay: Seconds = 30
    /**
     * The number of seconds old a queue task is when it is "expired" and should be deleted.
     * We do not recommend modifying this value because it risks losing data or taking up too much
     * space on the user's device.
     */
    public var backgroundQueueExpiredSeconds: Seconds = Seconds.secondsFromDays(3)

    /// To help you get setup with the SDK or debug SDK, change the log level of logs you
    /// wish to view from the SDK.
    public var logLevel: CioLogLevel = .error

    /**
     Automatic tracking of screen views will generate `screen`-type events on every screen transition within
        your application.
     */
    public var autoTrackScreenViews: Bool = false

    /**
     Handler to be called by our automatic screen tracker to generate `screen` event body variables. You can use
     this to override our defaults and pass custom values in the body of the `screen` event
     */
    public var autoScreenViewBody: (() -> [String: Any])?

    /**
     Enable this property if you want SDK to automatic tracking of device attributes such as
     operating system, device locale, device model, app version etc
     */
    public var autoTrackDeviceAttributes: Bool = true

    internal var httpBaseUrls: HttpBaseUrls {
        HttpBaseUrls(trackingApi: trackingApiUrl)
    }

    // property is used internally so disable swiftlint rule
    /**
     Used internally at Customer.io to override some information in the SDK when the SDK is being used
     as a wrapper/bridge such as with ReactNative.
     */
    public var _sdkWrapperConfig: SdkWrapperConfig? // swiftlint:disable:this identifier_name
}

public struct RichPushSdkConfig {
    public var trackingApiUrl: String
    public var autoTrackPushEvents: Bool
    public var logLevel: CioLogLevel
    public var autoTrackDeviceAttributes: Bool

    // Used to create new instance when the SDK is initialized.
    // Then, each property can be modified by the user.
    public enum Factory {
        public static func create(region: Region) -> RichPushSdkConfig {
            let defaultSdkConfig = SdkConfig.Factory.create(region: region)

            return RichPushSdkConfig(
                trackingApiUrl: defaultSdkConfig.trackingApiUrl,
                autoTrackPushEvents: defaultSdkConfig.autoTrackPushEvents,
                logLevel: defaultSdkConfig.logLevel,
                autoTrackDeviceAttributes: defaultSdkConfig.autoTrackDeviceAttributes
            )
        }
    }

    public func toSdkConfig() -> SdkConfig {
        var sdkConfig = SdkConfig(trackingApiUrl: trackingApiUrl)

        sdkConfig.autoTrackPushEvents = autoTrackPushEvents
        sdkConfig.logLevel = logLevel
        sdkConfig.autoTrackDeviceAttributes = autoTrackDeviceAttributes

        return sdkConfig
    }
}
