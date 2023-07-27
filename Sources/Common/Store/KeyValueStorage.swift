import Foundation

/**
 Stores data in key/value pairs.
 */
public protocol KeyValueStorage {
    func integer(_ key: KeyValueStorageKey) -> Int?
    func setInt(_ value: Int?, forKey key: KeyValueStorageKey)
    func double(_ key: KeyValueStorageKey) -> Double?
    func setDouble(_ value: Double?, forKey key: KeyValueStorageKey)
    func string(_ key: KeyValueStorageKey) -> String?
    func setString(_ value: String?, forKey key: KeyValueStorageKey)
    func stringList(_ key: KeyValueStorageKey) -> [String]?
    func setStringList(_ value: [String]?, forKey key: KeyValueStorageKey)
    func date(_ key: KeyValueStorageKey) -> Date?
    func setDate(_ value: Date?, forKey key: KeyValueStorageKey)
    func deleteAll()
    func migrate(from: KeyValueStorage)
}

/*
 Uses UserDefaults to store data in key/value pairs.
 */
// sourcery: InjectRegister = "KeyValueStorage"
open class UserDefaultsKeyValueStorage: KeyValueStorage {
    private var userDefaults: UserDefaults? {
        UserDefaults(suiteName: getStorageName())
    }

    init() {}

    // A string that represents the SDK and separates the SDK's data with all other data for the app.
    open func getStorageName() -> String {
        "io.customer.sdk"
    }

    public func integer(_ key: KeyValueStorageKey) -> Int? {
        let value = userDefaults?.integer(forKey: key.rawValue)
        return value == 0 ? nil : value
    }

    public func setInt(_ value: Int?, forKey key: KeyValueStorageKey) {
        userDefaults?.set(value, forKey: key.rawValue)
    }

    public func double(_ key: KeyValueStorageKey) -> Double? {
        let value = userDefaults?.double(forKey: key.rawValue)
        return value == 0 ? nil : value
    }

    public func setDouble(_ value: Double?, forKey key: KeyValueStorageKey) {
        userDefaults?.set(value, forKey: key.rawValue)
    }

    public func string(_ key: KeyValueStorageKey) -> String? {
        userDefaults?.string(forKey: key.rawValue)
    }

    public func setString(_ value: String?, forKey key: KeyValueStorageKey) {
        userDefaults?.set(value, forKey: key.rawValue)
    }

    public func stringList(_ key: KeyValueStorageKey) -> [String]? {
        userDefaults?.stringArray(forKey: key.rawValue) ?? []
    }

    public func setStringList(_ value: [String]?, forKey key: KeyValueStorageKey) {
        userDefaults?.set(value, forKey: key.rawValue)
    }

    public func date(_ key: KeyValueStorageKey) -> Date? {
        guard let millis = userDefaults?.double(forKey: key.rawValue), millis > 0 else {
            return nil
        }

        return Date(timeIntervalSince1970: millis)
    }

    public func setDate(_ value: Date?, forKey key: KeyValueStorageKey) {
        userDefaults?.set(value?.timeIntervalSince1970, forKey: key.rawValue)
    }

    public func deleteAll() {
        userDefaults?.deleteAll()
    }

    public func migrate(from: KeyValueStorage) {
        KeyValueStorageKey.allCases.forEach { key in
            if let value = from.integer(key), self.integer(key) == nil {
                setInt(value, forKey: key)
            } else if let value = from.double(key), self.double(key) == nil {
                setDouble(value, forKey: key)
            } else if let value = from.string(key), self.string(key) == nil {
                setString(value, forKey: key)
            } else if let value = from.date(key), self.date(key) == nil {
                setDate(value, forKey: key)
            } else if let value = from.stringList(key), self.stringList(key) == nil {
                setStringList(value, forKey: key)
            }
        }
    }
}
