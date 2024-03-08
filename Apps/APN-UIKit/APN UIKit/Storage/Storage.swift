import Foundation

protocol StorageManager {
    var cdnHost: String? { get set }
    var apiHost: String? { get set }
    var siteId: String? { get set }
    var cdpApiKey: String? { get set }
    var bgQDelay: String? { get set }
    var bgNumOfTasks: String? { get set }
    var isTrackScreenEnabled: Bool? { get set }
    var isTrackDeviceAttrEnabled: Bool? { get set }
    var isDebugModeEnabled: Bool? { get set }
    var userEmailId: String? { get set }
    var deviceToken: String? { get set }
    var didSetDefaults: Bool? { get set }
}

// sourcery: InjectRegisterShared = "Storage"
class Storage: StorageManager {
    private let userDefaults: UserDefaults

    // Initialization
    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    var deviceToken: String? {
        get {
            userDefaults.string(forKey: UserDefaultKeys.deviceToken.rawValue)
        }
        set {
            userDefaults.set(newValue, forKey: UserDefaultKeys.deviceToken.rawValue)
        }
    }

    var userEmailId: String? {
        get {
            userDefaults.string(forKey: UserDefaultKeys.userEmailId.rawValue)
        }
        set {
            userDefaults.set(newValue, forKey: UserDefaultKeys.userEmailId.rawValue)
        }
    }

    var siteId: String? {
        get {
            userDefaults.string(forKey: UserDefaultKeys.siteId.rawValue)
        }
        set {
            userDefaults.set(newValue, forKey: UserDefaultKeys.siteId.rawValue)
        }
    }

    var cdpApiKey: String? {
        get {
            userDefaults.string(forKey: UserDefaultKeys.cdpApiKey.rawValue)
        }
        set {
            userDefaults.set(newValue, forKey: UserDefaultKeys.cdpApiKey.rawValue)
        }
    }

    var bgQDelay: String? {
        get {
            userDefaults.string(forKey: UserDefaultKeys.bgQDelay.rawValue)
        }
        set {
            userDefaults.set(newValue, forKey: UserDefaultKeys.bgQDelay.rawValue)
        }
    }

    var bgNumOfTasks: String? {
        get {
            userDefaults.string(forKey: UserDefaultKeys.bgNumOfTasks.rawValue)
        }
        set {
            userDefaults.set(newValue, forKey: UserDefaultKeys.bgNumOfTasks.rawValue)
        }
    }

    var isTrackScreenEnabled: Bool? {
        get {
            userDefaults.bool(forKey: UserDefaultKeys.isTrackScreenEnabled.rawValue)
        }
        set {
            userDefaults.set(newValue, forKey: UserDefaultKeys.isTrackScreenEnabled.rawValue)
        }
    }

    var isTrackDeviceAttrEnabled: Bool? {
        get {
            userDefaults.bool(forKey: UserDefaultKeys.isTrackDeviceAttrEnabled.rawValue)
        }
        set {
            userDefaults.set(newValue, forKey: UserDefaultKeys.isTrackDeviceAttrEnabled.rawValue)
        }
    }

    var isDebugModeEnabled: Bool? {
        get {
            userDefaults.bool(forKey: UserDefaultKeys.isDebugModeEnabled.rawValue)
        }
        set {
            userDefaults.set(newValue, forKey: UserDefaultKeys.isDebugModeEnabled.rawValue)
        }
    }

    var didSetDefaults: Bool? {
        get {
            userDefaults.bool(forKey: UserDefaultKeys.didSetDefaults.rawValue)
        }
        set {
            userDefaults.set(newValue, forKey: UserDefaultKeys.didSetDefaults.rawValue)
        }
    }

    var apiHost: String? {
        get {
            userDefaults.string(forKey: UserDefaultKeys.apiHost.rawValue)
        }
        set {
            userDefaults.set(newValue, forKey: UserDefaultKeys.apiHost.rawValue)
        }
    }

    var cdnHost: String? {
        get {
            userDefaults.string(forKey: UserDefaultKeys.cdnHost.rawValue)
        }
        set {
            userDefaults.set(newValue, forKey: UserDefaultKeys.cdnHost.rawValue)
        }
    }
}
