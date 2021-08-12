import Foundation

internal protocol SdkConfigManager: AutoMockable {
    func load(siteId: String) -> SdkConfig?
    func create(siteId: String, apiKey: String, region: Region) -> SdkConfig
    func save(siteId: String, config: SdkConfig)
}

// sourcery: InjectRegister = "SdkConfigManager"
internal class CIOSdkConfigManager: SdkConfigManager {
    private let keyValueStorage: KeyValueStorage
    private let jsonAdapter: JsonAdapter

    internal init(keyValueStorage: KeyValueStorage, jsonAdapter: JsonAdapter) {
        self.keyValueStorage = keyValueStorage
        self.jsonAdapter = jsonAdapter
    }

    func load(siteId: String) -> SdkConfig? {
        guard let configString = keyValueStorage.string(forKey: .siteIdConfig(siteId: siteId)) else {
            return nil
        }

        let sdkConfig: SdkConfig = try! jsonAdapter.fromJson(configString.data)

        return sdkConfig
    }

    func create(siteId: String, apiKey: String, region: Region) -> SdkConfig {
        // Default config settings get set here.
        SdkConfig(siteId: siteId, apiKey: apiKey, regionCode: region.code) // devMode: false)
    }

    func save(siteId: String, config: SdkConfig) {
        let configString = try! jsonAdapter.toJson(config).string

        keyValueStorage.setString(configString, forKey: .siteIdConfig(siteId: siteId))
    }
}
