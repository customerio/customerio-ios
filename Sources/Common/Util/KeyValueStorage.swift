import Foundation

/**
 Stores data in key/value pairs.
 */
public protocol SharedKeyValueStorage {
    func integer(_ key: KeyValueStorageKey) -> Int?
    func setInt(_ value: Int?, forKey key: KeyValueStorageKey)
    func double(_ key: KeyValueStorageKey) -> Double?
    func setDouble(_ value: Double?, forKey key: KeyValueStorageKey)
    func string(_ key: KeyValueStorageKey) -> String?
    func setString(_ value: String?, forKey key: KeyValueStorageKey)
    func date(_ key: KeyValueStorageKey) -> Date?
    func setDate(_ value: Date?, forKey key: KeyValueStorageKey)
    func data(_ key: KeyValueStorageKey) -> Data?
    func setData(_ value: Data?, forKey key: KeyValueStorageKey)
    func deleteAll()
}

/**
 Key/Value storage that is sandboxed by a given siteId.

 This is to support legacy code before the CDP mobile SDK. So, we only need to have a couple methods instead of all of the methods that `SharedKeyValueStorage` has.
 */
public protocol SandboxedSiteIdKeyValueStorage {
    func string(_ key: KeyValueStorageKey, siteId: String) -> String?
    func setString(_ value: String?, forKey key: KeyValueStorageKey, siteId: String)
}

/*
 Uses UserDefaults to store data in key/value pairs.
 */
// sourcery: InjectRegisterShared = "SandboxedSiteIdKeyValueStorage"
public class UserDefaultsSandboxedSiteIdKVStore: SandboxedSiteIdKeyValueStorage {
    private let deviceMetricsGrabber: DeviceMetricsGrabber

    private func userDefaults(siteId: String) -> UserDefaults? {
        UserDefaults(suiteName: getFileName(siteId: siteId))
    }

    init(deviceMetricsGrabber: DeviceMetricsGrabber) {
        self.deviceMetricsGrabber = deviceMetricsGrabber
    }

    /**
     We want to sandbox all of the data for each CIO workspace and app.
     Therefore, we use the app's bundle ID to be unique to the app and the siteId to separate all of the sites.

     We also need to have 1 set of UserPreferences that all workspaces of an app share.
     For these moments, use `shared` as the `siteId` value.
     */
    func getFileName(siteId: String) -> String {
        var appUniqueIdentifier = ""
        if let appBundleId = deviceMetricsGrabber.appBundleId {
            appUniqueIdentifier = ".\(appBundleId)"
        }

        return "io.customer.sdk\(appUniqueIdentifier).\(siteId)"
    }

    public func string(_ key: KeyValueStorageKey, siteId: String) -> String? {
        userDefaults(siteId: siteId)?.string(forKey: key.rawValue)
    }

    public func setString(_ value: String?, forKey key: KeyValueStorageKey, siteId: String) {
        userDefaults(siteId: siteId)?.set(value, forKey: key.rawValue)
    }
}

// sourcery: InjectRegisterShared = "SharedKeyValueStorage"
public class UserDefaultsSharedKeyValueStorage: SharedKeyValueStorage {
    private let deviceMetricsGrabber: DeviceMetricsGrabber

    private var userDefaults: UserDefaults? {
        UserDefaults(suiteName: getFileName())
    }

    init(deviceMetricsGrabber: DeviceMetricsGrabber) {
        self.deviceMetricsGrabber = deviceMetricsGrabber
    }

    /**
     We want to sandbox all of the data for each CIO workspace and app.
     Therefore, we use the app's bundle ID to be unique to the app and the siteId to separate all of the sites.

     We also need to have 1 set of UserPreferences that all workspaces of an app share.
     For these moments, use `shared` as the `siteId` value.
     */
    func getFileName() -> String {
        var appUniqueIdentifier = ""
        if let appBundleId = deviceMetricsGrabber.appBundleId {
            appUniqueIdentifier = ".\(appBundleId)"
        }

        return "io.customer.sdk\(appUniqueIdentifier).shared"
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

    public func date(_ key: KeyValueStorageKey) -> Date? {
        guard let millis = userDefaults?.double(forKey: key.rawValue), millis > 0 else {
            return nil
        }

        return Date(timeIntervalSince1970: millis)
    }

    public func setDate(_ value: Date?, forKey key: KeyValueStorageKey) {
        userDefaults?.set(value?.timeIntervalSince1970, forKey: key.rawValue)
    }

    public func data(_ key: KeyValueStorageKey) -> Data? {
        userDefaults?.data(forKey: key.rawValue)
    }

    public func setData(_ value: Data?, forKey key: KeyValueStorageKey) {
        userDefaults?.set(value, forKey: key.rawValue)
    }

    public func deleteAll() {
        userDefaults?.deleteAll()
    }
}
