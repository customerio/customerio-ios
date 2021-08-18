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

     Note: Don't forget to call `CustomerIO.initialize()` before using this!
     */
    @Atomic public private(set) static var instance = CustomerIO()

    @Atomic internal var sdkConfig: SdkConfig
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

        self.sdkConfig = SdkConfig()
    }

    /**
     Make testing the singleton `instance` possible.
     Note: It's recommended to delete app data before doing this to prevent loading persisted credentials
     */
    internal static func resetSharedInstance() {
        Self.instance = CustomerIO()
    }

    /**
     Create an instance of `CustomerIO`.

     This is the recommended method for code bases containing
     automated tests, dependency injection, or sending data to multiple Workspaces.
     */
    public init(siteId: String, apiKey: String, region: Region) {
        self.sdkConfig = Self.instance.sdkConfig
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

        // Some default values of the SDK configuration may depend on credentials. Reset default values.
        sdkConfig = setDefaultValuesSdkConfig(config: sdkConfig)
    }

    /**
     Configure the Customer.io SDK.

     This will configure the singleton shared instance of the CustomerIO class. It will also be the defafult
     configuration for all future non-singleton instances of the CustomerIO class.

     Example use:
     ```
     CustomerIO.config {
       $0.onUnhandledError = { error in
         // log the error to fix
       }
     }
     ```
     */
    public static func config(_ handler: (inout SdkConfig) -> Void) {
        var configToModify = instance.sdkConfig

        handler(&configToModify)
        configToModify = instance.setDefaultValuesSdkConfig(config: configToModify)

        instance.sdkConfig = configToModify
    }

    /**
     Configure the Customer.io SDK.

     This will configure the given non-singleton instance of CustomerIO.
     Cofiguration changes will only impact this 1 instance of the CustomerIO class.

     Example use:
     ```
     CustomerIO.config {
       $0.onUnhandledError = { error in
         // log the error to fix
       }
     }
     ```
     */
    public func config(_ handler: (inout SdkConfig) -> Void) {
        var configToModify = sdkConfig

        handler(&configToModify)
        configToModify = setDefaultValuesSdkConfig(config: configToModify)

        sdkConfig = configToModify
    }

    private func setDefaultValuesSdkConfig(config: SdkConfig) -> SdkConfig {
        var config = config

        // if tracking API not set in the configuration, set to default production value.
        if config.trackingApiUrl.isEmpty, let credentials = self.credentials {
            config.trackingApiUrl = credentials.region.productionTrackingUrl
        }

        return config
    }
}
