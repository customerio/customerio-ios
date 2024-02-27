import Foundation
#if canImport(UIKit)
import UIKit
#endif

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
    // Used to create new instance of SdkConfig when the SDK is initialized.
    // Then, each property of the SdkConfig object can be modified by the user.
    public enum Factory {
        public static func create() -> SdkConfig {
            SdkConfig(
                logLevel: CioLogLevel.error
            )
        }
    }

    public mutating func modify(params: [String: Any]) {
        // Each SDK config option should be able to be set from `param` map.
        // If one isn't provided, use the default value instead.

        // If a parameter takes more logic to calculate, perform the logic up here.
        if let logLevelStringValue = params[Keys.logLevel.rawValue] as? String, let paramLogLevel =
            CioLogLevel.getLogLevel(for: logLevelStringValue) {
            logLevel = paramLogLevel
        }
    }

    // Constants that SDK wrappers can use with `modify` function for setting configuration options with strings.
    // It's important to keep these values backwards compatible to avoid breaking SDK wrappers.
    public enum Keys: String { // Constants used to map each of the options in SdkConfig
        // config features
        case logLevel
    }

    /// To help you get setup with the SDK or debug SDK, change the log level of logs you
    /// wish to view from the SDK.
    public var logLevel: CioLogLevel
}
