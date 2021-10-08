import Foundation

public protocol ProfileStore: AutoMockable {
    var identifier: String? { get set }
    var loggedOutIdentifier: String? { get set }

    func clearLoggedOutIdentifier()
}

// sourcery: InjectRegister = "ProfileStore"
public class CioProfileStore: ProfileStore {
    private let keyValueStorage: KeyValueStorage

    init(keyValueStorage: KeyValueStorage) {
        self.keyValueStorage = keyValueStorage
    }

    public var identifier: String? {
        get {
            keyValueStorage.string(.identifiedProfileId) ?? keyValueStorage.string(.loggedOutProfileId)
        }
        set {
            keyValueStorage.setString(newValue, forKey: .identifiedProfileId)
        }
    }

    public var loggedOutIdentifier: String? {
        get {
            keyValueStorage.string(.loggedOutProfileId)
        }
        set {
            keyValueStorage.setString(newValue, forKey: .loggedOutProfileId)
        }
    }

    public func clearLoggedOutIdentifier() {
        keyValueStorage.delete(forKey: .loggedOutProfileId)
    }
}
