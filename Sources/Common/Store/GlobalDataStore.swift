import Foundation

/// SDK data that is common between all site ids.
public protocol GlobalDataStore: AutoMockable {
    // APN or FCM device token
    var pushDeviceToken: String? { get set }

    // Cache the last response from HTTP request for the in-app user queue.
    var inAppUserQueueFetchCachedResponse: Data? { get set }

    // Used for testing
    func deleteAll()
}

// sourcery: InjectRegisterShared = "GlobalDataStore"
public class CioSharedDataStore: GlobalDataStore {
    private let keyValueStorage: SharedKeyValueStorage

    public var pushDeviceToken: String? {
        get {
            keyValueStorage.string(.pushDeviceToken)
        }
        set {
            keyValueStorage.setString(newValue, forKey: .pushDeviceToken)
        }
    }

    public var inAppUserQueueFetchCachedResponse: Data? {
        get {
            keyValueStorage.data(.inAppUserQueueFetchCachedResponse)
        }
        set {
            keyValueStorage.setData(newValue, forKey: .inAppUserQueueFetchCachedResponse)
        }
    }

    public init(keyValueStorage: SharedKeyValueStorage) {
        self.keyValueStorage = keyValueStorage
    }

    public func deleteAll() {
        keyValueStorage.deleteAll()
    }
}
