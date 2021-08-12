import Foundation

public enum Region: String {
    case US = "us"
    case EU = "eu"

    var code: String {
        rawValue
    }
}

public class CustomerIO {
    @Atomic public private(set) static var instance = CustomerIO()

    internal var config: SdkConfig?
    private var keyValueStorage: KeyValueStorage = DI.shared.inject(.keyValueStorage)
    private var configManager: SdkConfigManager = DI.shared.inject(.sdkConfigManager)

    internal init(keyValueStorage: KeyValueStorage, configManager: SdkConfigManager) {
        self.keyValueStorage = keyValueStorage
        self.configManager = configManager
    }

    /**
     Constructor for singleton, only.
     */
    internal init() {
        if let sharedInstanceSiteId = keyValueStorage.string(forKey: .sharedInstanceSiteId) {
            self.config = configManager.load(siteId: sharedInstanceSiteId)
        }
    }

    public init(siteId: String, apiKey: String, region: Region) {
        var config = configManager.load(siteId: siteId) ?? configManager.create(siteId: siteId, apiKey: apiKey, region: region)

        config = config.apiKeySet(apiKey).regionCodeSet(region.code)

        configManager.save(siteId: siteId, config: config)
    }

    public static func config(siteId: String, apiKey: String, region: Region) {
        var config = Self.instance.configManager.load(siteId: siteId) ?? Self.instance.configManager.create(siteId: siteId, apiKey: apiKey, region: region)

        config = config.apiKeySet(apiKey).regionCodeSet(region.code)

        Self.instance.configManager.save(siteId: siteId, config: config)
    }
}
