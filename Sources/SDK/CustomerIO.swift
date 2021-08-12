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
    private var configManager: SdkConfigManager = DI.shared.inject(.sdkConfigManager)

    /**
     init for tests
     */
    internal init(keyValueStorage: KeyValueStorage, configManager: SdkConfigManager) {
        self.keyValueStorage = keyValueStorage
        self.configManager = configManager
    }

    /**
     Constructor for singleton, only.
     */
    internal init() {
        if let siteId = keyValueStorage.string(siteId: keyValueStorage.sharedSiteId, forKey: .sharedInstanceSiteId) {
            self.config = configManager.load(siteId: siteId)
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
        var config = configManager.load(siteId: siteId)
            ?? configManager.create(siteId: siteId, apiKey: apiKey, region: region)

        config = config.apiKeySet(apiKey).regionSet(region)

        self.config = config
        configManager.save(siteId: siteId, config: config)
    }
}
