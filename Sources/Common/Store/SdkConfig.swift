import Foundation

/**
 Configuration options for the Customer.io SDK.
 See `CustomerIO.config()` to configurate the SDK.

 Example use case:
 ```
 // create a new instance
 let sdkConfigInstance = SdkConfig.Factory.create(region: .US)
 // now, you can modify it
 sdkConfigInstance.trackingApiUrl = "https..."
 sdkConfigInstance.autoTrackPushEvents = false
 ```
 */
public struct SdkConfig {
    public enum Environment {
        static let siteId = "siteId"
        static let apiKey = "apiKey"
        static let region = "region"
    }

    public enum Config {
        static let trackingApiUrl = "trackingApiUrl"
        static let autoTrackDeviceAttributes = "autoTrackDeviceAttributes"
        static let logLevel = "logLevel"
        static let autoTrackPushEvents = "autoTrackPushEvents"
        static let backgroundQueueMinNumberOfTasks = "backgroundQueueMinNumberOfTasks"
        static let backgroundQueueSecondsDelay = "backgroundQueueSecondsDelay"
    }

    public enum Package {
        static let source = "source"
        static let sourceVersion = "version"
       }

    // Used to create new instance of SdkConfig when the SDK is initialized.
    // Then, each property of the SdkConfig object can be modified by the user.
    public enum Factory {
        public static func create(region: Region, params: [String: Any] = [:]) -> SdkConfig {
            var config = SdkConfig(trackingApiUrl: region.productionTrackingUrl)
            if let autoTrackDeviceAttributes = params[Config.autoTrackDeviceAttributes] as? Bool {
                config.autoTrackDeviceAttributes = autoTrackDeviceAttributes
            }
            if let logLevel = params[Config.logLevel] as? String {
                config.logLevel = CioLogLevel.getLogLevel(for: logLevel)
            } else if let logLevel = params[Config.logLevel] as? Int {
                config.logLevel = CioLogLevel.getLogLevel(for: logLevel)
            }
            if let autoTrackPushEvents = params[Config.autoTrackPushEvents] as? Bool {
                config.autoTrackPushEvents = autoTrackPushEvents
            }
            if let backgroundQueueMinNumberOfTasks = params[Config.backgroundQueueMinNumberOfTasks] as? Int {
                config.backgroundQueueMinNumberOfTasks = backgroundQueueMinNumberOfTasks
            }
            if let backgroundQueueSecondsDelay = params[Config.backgroundQueueSecondsDelay] as? Int {
                config.backgroundQueueSecondsDelay = Seconds(backgroundQueueSecondsDelay)
            }
            if let sdkSource = params[Package.source] as? String, let pversion = params[Package.sourceVersion]  as? String, let sdkConfigSource = SdkWrapperConfig.Source(rawValue: sdkSource) {
                config._sdkWrapperConfig = SdkWrapperConfig(source: sdkConfigSource, version: pversion)
            }
            if let trackingApiUrl = params[Config.trackingApiUrl] as? String, !trackingApiUrl.isEmpty {
                config.trackingApiUrl = trackingApiUrl
            }
            return config
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

/**
 SDK configuration just for rich push feature of the SDK.

 Construct an instance like you would `SdkConfig`.

 We have a separate SDK config just for rich push because:
 1. Instance of SDK inside of a Notification Service Extension does not have as many features to provide
 compared to running in a host app. Therefore, we don't need to expose as many SDK config options to customers.
 2. The SDK code needs to override some configuration options when running inside of a Notication Service Extension.
 We don't want customers to modify some of these overriden config options as it may effect some features of rich push.

 Note: To not make the SDK code more complex, convert `NotificationServiceExtensionSdkConfig` to an instance of `SdkConfig` when SDK is initialized.
 The SDK should not have conditional logic handling different SDK config objects. The SDK should only have to handle `SdkConfig`.
 */
public struct NotificationServiceExtensionSdkConfig {
    /// See `SdkConfig.trackingApiUrl`
    public var trackingApiUrl: String
    /// See `SdkConfig.autoTrackPushEvents`
    public var autoTrackPushEvents: Bool
    /// See `SdkConfig.logLevel`
    public var logLevel: CioLogLevel
    /// See `SdkConfig.autoTrackDeviceAttributes`
    public var autoTrackDeviceAttributes: Bool
    // property is used internally so disable swiftlint rule
    /**
     Used internally at Customer.io to override some information in the SDK when the SDK is being used
     as a wrapper/bridge such as with ReactNative.
     */
    public var _sdkWrapperConfig: SdkWrapperConfig? // swiftlint:disable:this identifier_name

    // Used to create new instance when the SDK is initialized.
    // Then, each property can be modified by the user.
    public enum Factory {
        public static func create(region: Region) -> NotificationServiceExtensionSdkConfig {
            let defaultSdkConfig = SdkConfig.Factory.create(region: region)

            return NotificationServiceExtensionSdkConfig(
                trackingApiUrl: defaultSdkConfig.trackingApiUrl,
                autoTrackPushEvents: defaultSdkConfig.autoTrackPushEvents,
                logLevel: defaultSdkConfig.logLevel,
                autoTrackDeviceAttributes: defaultSdkConfig.autoTrackDeviceAttributes
            )
        }
    }

    /// Convert to `SdkConfig` before being used in the SDK. For make the SDK code base easier to maintain, the SDK is
    /// designed to only handle a `SdkCofig` object.
    /// Therefore, we need to convert this object to an `SdkConfig` instance in SDK initialization so the SDK can use
    /// it.
    public func toSdkConfig() -> SdkConfig {
        var sdkConfig = SdkConfig(trackingApiUrl: trackingApiUrl)

        sdkConfig.autoTrackPushEvents = autoTrackPushEvents
        sdkConfig.logLevel = logLevel
        sdkConfig.autoTrackDeviceAttributes = autoTrackDeviceAttributes
        sdkConfig._sdkWrapperConfig = _sdkWrapperConfig

        // Default to running tasks added to the BQ immediately.
        // Since a Notification Service Extension is only in memory for a small amount of time,
        // we need to bypass the background queue default behavior to make sure that HTTP tasks
        // have an opportunity to execute before the OS kills the Notification Service Extension.
        //
        // Customers should not be able to modify these values in a Notification Service Extension.
        // Or, they may experience some events (such as push metrics) not being delivered as expected to CIO.
        sdkConfig.backgroundQueueMinNumberOfTasks = 1
        sdkConfig.backgroundQueueSecondsDelay = 0

        return sdkConfig
    }
}
