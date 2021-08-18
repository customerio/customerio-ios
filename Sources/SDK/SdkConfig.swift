import Foundation

/**
 Configuration options for the Customer.io SDK.
 See `CustomerIO.config()` to configurate the SDK.
 */
public struct SdkConfig {
    /**
     Base URL to use for the Customer.io track API. You will more then likely not modify this value.

     If you override this value, `Region` set when initializing the SDK will be ignored.
     */
    var trackingApiUrl: String = ""

    internal var httpBaseUrls: HttpBaseUrls {
        HttpBaseUrls(trackingApi: trackingApiUrl)
    }
}
