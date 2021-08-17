import Foundation

internal protocol SdkConfigStore: AutoMockable {
    var sharedInstanceSiteId: String? { get set }
    func load(siteId: String) -> SdkConfig?
    func create(siteId: String, apiKey: String, region: Region) -> SdkConfig
    func save(siteId: String, config: SdkConfig)
}

// sourcery: InjectRegister = "SdkConfigStore"
internal class CIOSdkConfigStore: SdkConfigStore {
    private var keyValueStorage: KeyValueStorage

    internal init(keyValueStorage: KeyValueStorage) {
        self.keyValueStorage = keyValueStorage
    }

    var sharedInstanceSiteId: String? {
        get {
            keyValueStorage.string(siteId: keyValueStorage.sharedSiteId, forKey: .sharedInstanceSiteId)
        }
        set {
            keyValueStorage.setString(siteId: keyValueStorage.sharedSiteId, value: newValue,
                                      forKey: .sharedInstanceSiteId)
        }
    }

    func load(siteId: String) -> SdkConfig? {
        // try to load the required params
        // else, return nil as we don't have enough information to perform any action in the SDK.
        guard let apiKey = keyValueStorage.string(siteId: siteId, forKey: .apiKey),
              let regionCode = keyValueStorage.string(siteId: siteId, forKey: .regionCode),
              let region = Region(rawValue: regionCode)
        else {
            return nil
        }

        return SdkConfig(siteId: siteId,
                         apiKey: apiKey,
                         region: region)
    }

    func create(siteId: String, apiKey: String, region: Region) -> SdkConfig {
        SdkConfig(siteId: siteId, apiKey: apiKey, region: region)
    }

    func save(siteId: String, config: SdkConfig) {
        keyValueStorage.setString(siteId: siteId, value: config.apiKey, forKey: .apiKey)
        keyValueStorage.setString(siteId: siteId, value: config.region.rawValue, forKey: .regionCode)
    }
}
