import Foundation

internal protocol SdkConfigManager: AutoMockable {
    func load(siteId: String) -> SdkConfig?
    func create(siteId: String, apiKey: String, region: Region) -> SdkConfig
    func save(siteId: String, config: SdkConfig)
}

// sourcery: InjectRegister = "SdkConfigManager"
internal class CIOSdkConfigManager: SdkConfigManager {
    private var keyValueStorage: KeyValueStorage
    private let jsonAdapter: JsonAdapter

    internal init(keyValueStorage: KeyValueStorage, jsonAdapter: JsonAdapter) {
        self.keyValueStorage = keyValueStorage
        self.jsonAdapter = jsonAdapter
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
        keyValueStorage.setString(siteId: siteId, value: config.region.code, forKey: .regionCode)
    }
}
