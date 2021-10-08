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
     Automatically generate a customer profile in Customer.io before login. If this option is enabled we will
     create a person in Customer.io prior to your initial `identify` call, which will then allow you to send
     pushes through Customer.io to users even if they are not logged in or signed up
     */
    public var enablePreLoginTracking: Bool = false // XXX: need an actual name for the feature

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
