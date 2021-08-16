import Foundation

/**
 Stores data in key/value pairs.
 */
internal protocol KeyValueStorage: AutoMockable {
    var sharedSiteId: String { get }

    func integer(siteId: String, forKey key: KeyValueStorageKey) -> Int?
    func setInt(siteId: String, value: Int?, forKey key: KeyValueStorageKey)
    func double(siteId: String, forKey key: KeyValueStorageKey) -> Double?
    func setDouble(siteId: String, value: Double?, forKey key: KeyValueStorageKey)
    func string(siteId: String, forKey key: KeyValueStorageKey) -> String?
    func setString(siteId: String, value: String?, forKey key: KeyValueStorageKey)
    func date(siteId: String, forKey key: KeyValueStorageKey) -> Date?
    func setDate(siteId: String, value: Date?, forKey key: KeyValueStorageKey)
    func deleteAll(siteId: String)
}

/**
 Uses UserDefaults to store data in key/value pairs.
 */
// sourcery: InjectRegister = "KeyValueStorage"
internal class UserDefaultsKeyValueStorage: KeyValueStorage {
    var sharedSiteId: String {
        "shared"
    }

    /**
     We want to separate all of the data for each CIO workspace and app.
     Therefore, we use the app's bundle ID to be unique to the app and the siteId to separate all of the sites.

     We also need to have 1 set of UserPreferences that all workspaces of an app share.
     For these moments, use `sharedSiteId` as the `siteId` parameter.
     */
    private func getUserDefaults(siteId: String) -> UserDefaults? {
        var appUniqueIdentifier = ""
        if let appBundleId = DeviceMetricsGrabber.appBundleId {
            appUniqueIdentifier = ".\(appBundleId)"
        }

        return UserDefaults(suiteName: "io.customer.sdk\(appUniqueIdentifier).\(siteId)")
    }

    func integer(siteId: String, forKey key: KeyValueStorageKey) -> Int? {
        let value = getUserDefaults(siteId: siteId)?.integer(forKey: key.rawValue)
        return value == 0 ? nil : value
    }

    func setInt(siteId: String, value: Int?, forKey key: KeyValueStorageKey) {
        getUserDefaults(siteId: siteId)?.set(value, forKey: key.rawValue)
    }

    func double(siteId: String, forKey key: KeyValueStorageKey) -> Double? {
        let value = getUserDefaults(siteId: siteId)?.double(forKey: key.rawValue)
        return value == 0 ? nil : value
    }

    func setDouble(siteId: String, value: Double?, forKey key: KeyValueStorageKey) {
        getUserDefaults(siteId: siteId)?.set(value, forKey: key.rawValue)
    }

    func string(siteId: String, forKey key: KeyValueStorageKey) -> String? {
        getUserDefaults(siteId: siteId)?.string(forKey: key.rawValue)
    }

    func setString(siteId: String, value: String?, forKey key: KeyValueStorageKey) {
        getUserDefaults(siteId: siteId)?.set(value, forKey: key.rawValue)
    }

    func date(siteId: String, forKey key: KeyValueStorageKey) -> Date? {
        guard let millis = getUserDefaults(siteId: siteId)?.double(forKey: key.rawValue), millis > 0 else {
            return nil
        }

        return Date(timeIntervalSince1970: millis)
    }

    func setDate(siteId: String, value: Date?, forKey key: KeyValueStorageKey) {
        getUserDefaults(siteId: siteId)?.set(value?.timeIntervalSince1970, forKey: key.rawValue)
    }

    func deleteAll(siteId: String) {
        getUserDefaults(siteId: siteId)?.deleteAll()
    }
}
