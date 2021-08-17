import Foundation

/**
 Welcome to the Customer.io iOS SDK!

 This class is where you begin to use the SDK.
 You must have an instance of `CustomerIO` to use the features of the SDK.

 To get an instance, you have 2 options:
 1. Use the already provided singleton shared instance: `CustomerIO.instance`.
 This method is provided for convenience and is the easiest way to get started.

 2. Create your own instance: `CustomerIO(siteId: "XXX", apiKey: "XXX", region: Region.US)`
 This method is recommended for code bases containing
 automated tests, dependency injection, or sending data to multiple Workspaces.
 */
public class CustomerIO {
    /**
     Singleton shared instance of `CustomerIO`. Convenient way to use the SDK.

     Note: Don't forget to call `CustomerIO.initialize(siteId: "XXX", apiKey: "XXX", region: Region.US)` before using this!
     */
    @Atomic public private(set) static var instance = CustomerIO()

    @Atomic internal var sdkConfig = SdkConfig()
    @Atomic internal var credentials: SdkCredentials?
    private var credentialsStore: SdkCredentialsStore = DI.shared.inject(.sdkCredentialsStore)

    /**
     init for testing
     */
    internal init(credentialsStore: SdkCredentialsStore, sdkConfig: SdkConfig) {
        self.credentialsStore = credentialsStore
        self.sdkConfig = sdkConfig
    }

    /**
     Constructor for singleton, only.

     Try loading the credentials previously saved for the singleton instance.
     */
    internal init() {
        if let siteId = credentialsStore.sharedInstanceSiteId {
            self.credentials = credentialsStore.load(siteId: siteId)
        }
    }

    /**
     Create an instance of `CustomerIO`.

     This is the recommended method for code bases containing
     automated tests, dependency injection, or sending data to multiple Workspaces.
     */
    public init(siteId: String, apiKey: String, region: Region) {
        setCredentials(siteId: siteId, apiKey: apiKey, region: region)
    }

    /**
     Initialize the shared `instance` of `CustomerIO`.
     Call this function when your app launches, before using `CustomerIO.instance`.
     */
    public static func initialize(siteId: String, apiKey: String, region: Region) {
        Self.instance.setCredentials(siteId: siteId, apiKey: apiKey, region: region)

        Self.instance.credentialsStore.sharedInstanceSiteId = siteId
    }

    internal func setCredentials(siteId: String, apiKey: String, region: Region) {
        var credentials = credentialsStore.load(siteId: siteId)
            ?? credentialsStore.create(siteId: siteId, apiKey: apiKey, region: region)

        credentials = credentials.apiKeySet(apiKey).regionSet(region)

        self.credentials = credentials
        credentialsStore.save(siteId: siteId, credentials: credentials)
    }

    public static func config(_ handler: (SdkConfig) -> Void) {
        let configToModify = instance.sdkConfig

        handler(configToModify)

        instance.sdkConfig = configToModify
    }

    public func config(_ handler: (SdkConfig) -> Void) {
        let configToModify = sdkConfig

        handler(configToModify)

        sdkConfig = configToModify
    }
}
