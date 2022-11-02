import Foundation

/**
 Stores data in key/value pairs.
 */
public protocol KeyValueStorage: AutoMockable {
    func integer(_ key: KeyValueStorageKey) -> Int?
    func setInt(_ value: Int?, forKey key: KeyValueStorageKey)
    func double(_ key: KeyValueStorageKey) -> Double?
    func setDouble(_ value: Double?, forKey key: KeyValueStorageKey)
    func string(_ key: KeyValueStorageKey) -> String?
    func setString(_ value: String?, forKey key: KeyValueStorageKey)
    func date(_ key: KeyValueStorageKey) -> Date?
    func setDate(_ value: Date?, forKey key: KeyValueStorageKey)
    func deleteAll()
}

/**
 Uses UserDefaults to store data in key/value pairs.
 */
// sourcery: InjectRegister = "KeyValueStorage"
public class UserDefaultsKeyValueStorage: KeyValueStorage {
    private let siteId: String?

    init(siteId: SiteId) {
        self.siteId = siteId
    }

    // Used for global data storing for *all* of the site-ids.
    init() {
        self.siteId = nil
    }

    /**
     We want to separate all of the data for each CIO workspace and app.
     Therefore, we use the app's bundle ID to be unique to the app and the siteId to separate all of the sites.

     We also need to have 1 set of UserPreferences that all workspaces of an app share.
     For these moments, use `sharedSiteId` as the `siteId` parameter.
     */
    private func getUserDefaults() -> UserDefaults? {
        var appUniqueIdentifier = ""
        if let appBundleId = DeviceMetricsGrabber.appBundleId {
            appUniqueIdentifier = ".\(appBundleId)"
        }

        // TODO: make test for this function

        var siteIdPart = ".shared"
        if let siteId = siteId {
            siteIdPart = ".\(siteId)"
        }

        return UserDefaults(suiteName: "io.customer.sdk\(appUniqueIdentifier)\(siteIdPart)")
    }

    public func integer(_ key: KeyValueStorageKey) -> Int? {
        let value = getUserDefaults()?.integer(forKey: key.rawValue)
        return value == 0 ? nil : value
    }

    public func setInt(_ value: Int?, forKey key: KeyValueStorageKey) {
        getUserDefaults()?.set(value, forKey: key.rawValue)
    }

    public func double(_ key: KeyValueStorageKey) -> Double? {
        let value = getUserDefaults()?.double(forKey: key.rawValue)
        return value == 0 ? nil : value
    }

    public func setDouble(_ value: Double?, forKey key: KeyValueStorageKey) {
        getUserDefaults()?.set(value, forKey: key.rawValue)
    }

    public func string(_ key: KeyValueStorageKey) -> String? {
        getUserDefaults()?.string(forKey: key.rawValue)
    }

    public func setString(_ value: String?, forKey key: KeyValueStorageKey) {
        getUserDefaults()?.set(value, forKey: key.rawValue)
    }

    public func date(_ key: KeyValueStorageKey) -> Date? {
        guard let millis = getUserDefaults()?.double(forKey: key.rawValue), millis > 0 else {
            return nil
        }

        return Date(timeIntervalSince1970: millis)
    }

    public func setDate(_ value: Date?, forKey key: KeyValueStorageKey) {
        getUserDefaults()?.set(value?.timeIntervalSince1970, forKey: key.rawValue)
    }

    public func deleteAll() {
        getUserDefaults()?.deleteAll()
    }
}
