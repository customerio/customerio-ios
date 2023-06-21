import Foundation

public class KeyValueStore {
    private let userDefaults = UserDefaults.standard

    public init() {}

    public var loggedInUserEmail: String? {
        get {
            userDefaults.string(forKey: Keys.loggedInUserEmail.rawValue)
        }
        set {
            userDefaults.set(newValue, forKey: Keys.loggedInUserEmail.rawValue)
        }
    }

    public var cioSettings: CioSettings? {
        get {
            guard let settingsData = userDefaults.data(forKey: Keys.cioSettings.rawValue) else {
                return nil
            }

            return try! JSONDecoder().decode(CioSettings.self, from: settingsData)
        }
        set {
            guard let newValue = newValue else {
                userDefaults.removeObject(forKey: Keys.cioSettings.rawValue)
                return
            }

            userDefaults.set(try! JSONEncoder().encode(newValue), forKey: Keys.cioSettings.rawValue)
        }
    }

    private enum Keys: String {
        case loggedInUserEmail
        case cioSettings
    }
}
