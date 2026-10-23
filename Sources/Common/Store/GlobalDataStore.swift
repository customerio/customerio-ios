import Foundation

/// SDK data that is common between all site ids.
public protocol GlobalDataStore: AutoMockable {
    // APN or FCM device token
    var pushDeviceToken: String? { get set }
    // Type of `pushDeviceToken`, when the SDK knows it
    var pushDeviceTokenType: DeviceTokenType? { get set }

    // Used for testing
    func deleteAll()
}

public extension GlobalDataStore {
    /// Saves the device token with its type.
    /// Saving the same token without a type keeps the stored type, so re-registering a stored token doesn't drop it.
    mutating func savePushDeviceToken(_ deviceToken: String, type: DeviceTokenType?) {
        if type != nil || deviceToken != pushDeviceToken {
            pushDeviceTokenType = type
        }
        pushDeviceToken = deviceToken
    }

    /// Whether the token is already stored. A token whose type isn't stored yet counts as not stored, so it gets one.
    func isPushDeviceTokenStored(_ deviceToken: String, type: DeviceTokenType?) -> Bool {
        deviceToken == pushDeviceToken && (type == nil || type == pushDeviceTokenType)
    }
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

    public var pushDeviceTokenType: DeviceTokenType? {
        get {
            keyValueStorage.string(.pushDeviceTokenType).flatMap(DeviceTokenType.init(rawValue:))
        }
        set {
            keyValueStorage.setString(newValue?.rawValue, forKey: .pushDeviceTokenType)
        }
    }

    public init(keyValueStorage: SharedKeyValueStorage) {
        self.keyValueStorage = keyValueStorage
    }

    public func deleteAll() {
        keyValueStorage.deleteAll()
    }
}
