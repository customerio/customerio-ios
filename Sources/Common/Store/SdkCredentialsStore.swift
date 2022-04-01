import Foundation

public protocol SdkCredentialsStore: AutoMockable {
    var credentials: SdkCredentials { get set }
    func load() -> SdkCredentials?
}

// sourcery: InjectRegister = "SdkCredentialsStore"
public class CIOSdkCredentialsStore: SdkCredentialsStore {
    private var keyValueStorage: KeyValueStorage

    // there is always a chance of credentials being nil since they are persisted in storage
    // and that storage can be deleted at any time. therefore, use a cache to always have
    // a value we can count on.
    @Atomic internal var cache: SdkCredentials?

    internal init(keyValueStorage: KeyValueStorage) {
        self.keyValueStorage = keyValueStorage
    }

    public var credentials: SdkCredentials {
        get {
            cache ?? load()!
        }
        set {
            save(newValue)
        }
    }

    @discardableResult
    public func load() -> SdkCredentials? {
        // try to load the required params
        // else, return nil as we don't have enough information to perform any action in the SDK.
        guard let apiKey = keyValueStorage.string(.apiKey),
              let regionCode = keyValueStorage.string(.regionCode),
              let region = Region(rawValue: regionCode)
        else {
            return nil
        }

        cache = SdkCredentials(apiKey: apiKey,
                               region: region)

        return cache
    }

    func save(_ credentials: SdkCredentials) {
        keyValueStorage.setString(credentials.apiKey, forKey: .apiKey)
        keyValueStorage.setString(credentials.region.rawValue, forKey: .regionCode)

        // to set the cache with new value
        load()
    }
}
