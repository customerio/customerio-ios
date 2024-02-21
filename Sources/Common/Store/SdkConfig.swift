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
        public static func create(siteId: String, apiKey: String, region: Region) -> SdkConfig {
            SdkConfig(
                siteId: siteId,
                apiKey: apiKey,
                region: region,
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

        // Construct object with all required parameters. Each config option should be provided from `params` or a default value.
        // Define default values here in constructor instead of in struct properties. This is by design so in the future if we add
        // a new SDK config option to the struct, we get a compiler error here in the constructor reminding us that we need to
        // add a way for `params` to override the SDK config option.

        if let sdkSource = params[Keys.source.rawValue] as? String, let pversion = params[Keys.sourceVersion.rawValue] as? String, let sdkConfigSource = SdkWrapperConfig.Source(rawValue: sdkSource) {
            _sdkWrapperConfig = SdkWrapperConfig(source: sdkConfigSource, version: pversion)
        }
    }

    // Constants that SDK wrappers can use with `modify` function for setting configuration options with strings.
    // It's important to keep these values backwards compatible to avoid breaking SDK wrappers.
    public enum Keys: String { // Constants used to map each of the options in SdkConfig
        // configure workspace environment
        case siteId
        case apiKey
        case region
        // config features
        case logLevel
        // SDK wrapper config
        case source
        case sourceVersion = "version"
    }

    /// Immutable property to store the workspace site id set during SDK initialization.
    public let siteId: String

    /// Immutable property to store the workspace api key set during SDK initialization.
    public let apiKey: String

    /// Immutable property to store the workspace Region set during SDK initialization.
    public let region: Region

    /// To help you get setup with the SDK or debug SDK, change the log level of logs you
    /// wish to view from the SDK.
    public var logLevel: CioLogLevel

    // property is used internally so disable swiftlint rule
    /**
     Used internally at Customer.io to override some information in the SDK when the SDK is being used
     as a wrapper/bridge such as with ReactNative.
     */
    public var _sdkWrapperConfig: SdkWrapperConfig? // swiftlint:disable:this identifier_name
}
