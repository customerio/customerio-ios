import Foundation

/// SDK data that is common between all site ids.
public protocol GlobalDataStore: AutoMockable {
    // APN or FCM device token
    var pushDeviceToken: String? { get set }
    // HTTP requests can be paused to avoid spamming the API too hard.
    // This Date is when a pause is able to be lifted.
    var httpRequestsPauseEnds: Date? { get set }

    // Used for testing
    func deleteAll()
}

/*
 A datastore that is not tied to a specific site-id. This is data that is to be shared across all site-ids.

 For example, device tokens. Device tokens are tied to a device and therefore, the value can be used between many different site-ids.

 At this time, this object is added to the DI graph as that is still the preferred way to get an instance of it as it makes automated tests easier to write. However, for some use cases you need to get an instance of this class before the DI graph is constructed. In those scenarios, this class provides a way to get an instance not from the DI graph.
 */

// sourcery: InjectRegister = "GlobalDataStore"
public class CioGlobalDataStore: GlobalDataStore {
    private let keyValueStorage: KeyValueStorage

    public var pushDeviceToken: String? {
        get {
            keyValueStorage.string(.pushDeviceToken)
        }
        set {
            keyValueStorage.setString(newValue, forKey: .pushDeviceToken)
        }
    }

    public var httpRequestsPauseEnds: Date? {
        get {
            keyValueStorage.date(.httpRequestsPauseEnds)
        }
        set {
            keyValueStorage.setDate(newValue, forKey: .httpRequestsPauseEnds)
        }
    }

    // constructor for automated tests to inject dependencies and also the constructor used by DI graph
    public init(keyValueStorage: GlobalKeyValueStorage) {
        self.keyValueStorage = keyValueStorage
    }

    // How to get instance before DI graph is constructed
    public static func getInstance() -> GlobalDataStore {
        CioGlobalDataStore(keyValueStorage: GlobalKeyValueStorage.getInstance())
    }

    public func deleteAll() {
        keyValueStorage.deleteAll()
    }
}
