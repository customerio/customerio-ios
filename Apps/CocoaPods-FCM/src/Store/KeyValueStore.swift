import Foundation

class KeyValueStore {
    private let userDefaults = UserDefaults.standard

    var loggedInUserEmail: String? {
        get {
            userDefaults.string(forKey: Keys.loggedInUserEmail.rawValue)
        }
        set {
            userDefaults.set(newValue, forKey: Keys.loggedInUserEmail.rawValue)
        }
    }

    enum Keys: String {
        case loggedInUserEmail
    }
}
