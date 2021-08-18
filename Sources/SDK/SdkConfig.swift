import Foundation

/**
 Configuration options for the Customer.io SDK.
 See `CustomerIO.config()` to configurate the SDK.
 */
public struct SdkConfig {
    /**
     Callback function called when an error occurs in the SDK.
     It's recommended to log the errors and report them to Cutomer.io support.
     */
    var onUnhandledError: ((Error) -> Void)?
}
