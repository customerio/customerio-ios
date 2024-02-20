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

    public var httpRequestsPauseEnds: Date? {
        get {
            keyValueStorage.date(.httpRequestsPauseEnds)
        }
        set {
            keyValueStorage.setDate(newValue, forKey: .httpRequestsPauseEnds)
        }
    }

    public init(keyValueStorage: SharedKeyValueStorage) {
        self.keyValueStorage = keyValueStorage
    }

    public func deleteAll() {
        keyValueStorage.deleteAll()
    }
}
