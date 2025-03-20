import Foundation

protocol StorageManager {
    var settings: Settings? { get set }
    var userEmailId: String? { get set }
    var didSetDefaults: Bool? { get set }
}

// sourcery: InjectRegisterShared = "Storage"
class Storage: StorageManager {
    private let userDefaults: UserDefaults

    // Initialization
    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    var settings: Settings? {
        get {
            guard let data = userDefaults.data(forKey: UserDefaultKeys.settings.rawValue) else { return nil }
            let settings = try? JSONDecoder().decode(Settings.self, from: data)
            return settings
        }
        set {
            guard let settings = newValue,
                  let data = try? JSONEncoder().encode(settings) else { return }
            userDefaults.set(data, forKey: UserDefaultKeys.settings.rawValue)
        }
    }

    var didSetDefaults: Bool? {
        get {
            userDefaults.bool(forKey: UserDefaultKeys.didSetSettingDefaults.rawValue)
        }
        set {
            userDefaults.set(newValue, forKey: UserDefaultKeys.didSetSettingDefaults.rawValue)
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
}
