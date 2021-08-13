import Foundation

// swiftlint:disable identifier_name
public enum Region: String, Equatable {
    case US = "us"
    case EU = "eu"

    var code: String {
        rawValue
    }
}

// swiftlint:enable identifier_name

public class CustomerIO {
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
     */
    internal init() {
        if let siteId = keyValueStorage.string(siteId: keyValueStorage.sharedSiteId, forKey: .sharedInstanceSiteId) {
            self.config = configStore.load(siteId: siteId)
        }
    }

    /**
     Create an instance of the CustomerIO SDK.
     */
    public init(siteId: String, apiKey: String, region: Region) {
        setConfig(siteId: siteId, apiKey: apiKey, region: region)
    }

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
