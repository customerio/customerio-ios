import Foundation

// swiftlint:disable identifier_name
/**
 Region that your Customer.io Workspace is located in.

 The SDK will route traffic to the correct data center location depending on the `Region` that you use.
 */
public enum Region: String, Equatable {
    /// The United States (US) data center
    case US = "us"
    /// The European Union (EU) data center
    case EU = "eu"

    internal var code: String {
        rawValue
    }
}

// swiftlint:enable identifier_name

/**
 Welcome to the Customer.io iOS SDK!

 This class is where you begin to use the SDK.

 To get an instance, you have 2 options:
 1. Use the already provided singleton shared instance: `CustomerIO.instance`.
 This method is provided for convenience and is the easiest way to get started.

 2. Create your own instance: `CustomerIO(siteId: "XXX", apiKey: "XXX", region: Region.US)`
 This method is recommended for code bases containing
 automated tests, dependency injection, or sending data to multiple workspaces.
 */
public class CustomerIO {
    /**
     Singleton shared instance of `CustomerIO`. Convenient way to use the SDK.

     Note: Don't forget to call `CustomerIO.config(siteId: "XXX", apiKey: "XXX", region: Region.US)` before using this!
     */
    @Atomic public private(set) static var instance = CustomerIO()

    @Atomic internal var config: SdkConfig?
    private var keyValueStorage: KeyValueStorage = DI.shared.inject(.keyValueStorage)
    private var configStore: SdkConfigStore = DI.shared.inject(.sdkConfigStore)

    /**
     init for tests
     */
    internal init(keyValueStorage: KeyValueStorage, configStore: SdkConfigStore) {
        self.keyValueStorage = keyValueStorage
        self.configStore = configStore
    }

    /**
     Constructor for singleton, only.

     Try loading the configuration previously saved for the singleton instance.
     */
    internal init() {
        if let siteId = keyValueStorage.string(siteId: keyValueStorage.sharedSiteId, forKey: .sharedInstanceSiteId) {
            self.config = configStore.load(siteId: siteId)
        }
    }

    /**
     Create an instance of `CustomerIO`.

     This is the recommended method for code bases containing
     automated tests, dependency injection, or sending data to multiple workspaces.
     */
    public init(siteId: String, apiKey: String, region: Region) {
        setConfig(siteId: siteId, apiKey: apiKey, region: region)
    }

    /**
     Configure the shared `instance` of `CustomerIO`.
     Call this function when your app launches, before using `CustomerIO.instance`.
     */
    public static func config(siteId: String, apiKey: String, region: Region) {
        Self.instance.setConfig(siteId: siteId, apiKey: apiKey, region: region)

        let keyValueStorage = Self.instance.keyValueStorage
        keyValueStorage.setString(siteId: keyValueStorage.sharedSiteId, value: siteId, forKey: .sharedInstanceSiteId)
    }

    internal func setConfig(siteId: String, apiKey: String, region: Region) {
        var config = configStore.load(siteId: siteId)
            ?? configStore.create(siteId: siteId, apiKey: apiKey, region: region)

        config = config.apiKeySet(apiKey).regionSet(region)

        self.config = config
        configStore.save(siteId: siteId, config: config)
    }
}
