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

    /**
     Automatic tracking of push events will automatically generate `opened` and `delivered` metrics
     for push notifications sent by Customer.io
     */
    public var autoTrackPushEvents: Bool = true

    /**
     Automatic tracking of screen views will generate `screen`-type events on every screen transition within
        your application. If you would prefer to handle these yourself, disable this feature
     */
    public var autoTrackScreenViews: Bool = true

    internal var httpBaseUrls: HttpBaseUrls {
        HttpBaseUrls(trackingApi: trackingApiUrl)
    }
}

public protocol SdkConfigStore: AutoMockable {
    var config: SdkConfig { get set }
}

// sourcery: InjectRegister = "SdkConfigStore"
// sourcery: InjectSingleton
public class InMemorySdkConfigStore: SdkConfigStore {
    @Atomic public var config = SdkConfig()
}
