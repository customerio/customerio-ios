import Foundation

/**
 Stores data in key/value pairs.
 */
internal protocol KeyValueStorage: AutoMockable {
    func integer(forKey key: KeyValueStorageKey) -> Int?
    func setInt(_ value: Int?, forKey key: KeyValueStorageKey)
    func double(forKey key: KeyValueStorageKey) -> Double?
    func setDouble(_ value: Double?, forKey key: KeyValueStorageKey)
    func string(forKey key: KeyValueStorageKey) -> String?
    func setString(_ value: String?, forKey key: KeyValueStorageKey)
    func date(forKey key: KeyValueStorageKey) -> Date?
    func setDate(_ value: Date?, forKey key: KeyValueStorageKey)
    func deleteAll()
}

/**
 Uses UserDefaults to store data in key/value pairs.
 */
// sourcery: InjectRegister = "KeyValueStorage"
internal class UserDefaultsKeyValueStorage: KeyValueStorage {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    func integer(forKey key: KeyValueStorageKey) -> Int? {
        let value = userDefaults.integer(forKey: key.string)
        return value == 0 ? nil : value
    }

    func setInt(_ value: Int?, forKey key: KeyValueStorageKey) {
        userDefaults.set(value, forKey: key.string)
    }

    func double(forKey key: KeyValueStorageKey) -> Double? {
        let value = userDefaults.double(forKey: key.string)
        return value == 0 ? nil : value
    }

    func setDouble(_ value: Double?, forKey key: KeyValueStorageKey) {
        userDefaults.set(value, forKey: key.string)
    }

    func string(forKey key: KeyValueStorageKey) -> String? {
        userDefaults.string(forKey: key.string)
    }

    func setString(_ value: String?, forKey key: KeyValueStorageKey) {
        userDefaults.set(value, forKey: key.string)
    }

    func date(forKey key: KeyValueStorageKey) -> Date? {
        let millis = userDefaults.double(forKey: key.string)
        guard millis > 0 else {
            return nil
        }

        return Date(timeIntervalSince1970: millis)
    }

    func setDate(_ value: Date?, forKey key: KeyValueStorageKey) {
        userDefaults.set(value?.timeIntervalSince1970, forKey: key.string)
    }

    func deleteAll() {
        userDefaults.dictionaryRepresentation().keys.forEach { key in
            if key.starts(with: KeyValueStorageKey.keyPrefix) {
                userDefaults.removeObject(forKey: key)
            }
        }
    }
}
