import Foundation

/**
 A version of KeyValueStorage that does not store data to a specific site-id. The data stored here is meant to be shared amongst all site-ids.
 
 We are using a typealias here as a way to tell the DI graph that GlobalKeyValueStorage is a separate data type to KeyValueStorage.
 */
public typealias GlobalKeyValueStorage = KeyValueStorage

// Typealiases cannot use the "InjectRegister" annotation so, we need to add the dependency manually to the DI graph.
// When a class needs GlobalKeyValueStorage as a dependency, it can just put GlobalKeyValueStorage in the constructor just like
// any other dependency. The DI graph will keep GlobalKeyValueStorage and KeyValueStorage separate.
public extension DIGraph {
    var globalKeyValueStorage: GlobalKeyValueStorage {
        let newInstance = UserDefaultsKeyValueStorage(siteId: "", deviceMetricsGrabber: DeviceMetricsGrabberImpl())
        newInstance.switchToGlobalDataStore()
        
        return getOverrideInstance() ?? newInstance
    }
}

/**
 Stores data in key/value pairs.
 */
public protocol KeyValueStorage {
    func switchToGlobalDataStore()

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

/*
 Uses UserDefaults to store data in key/value pairs.
 */
// sourcery: InjectRegister = "KeyValueStorage"
public class UserDefaultsKeyValueStorage: KeyValueStorage {
    private var siteId: String?
    private let deviceMetricsGrabber: DeviceMetricsGrabber

    private var userDefaults: UserDefaults? {
        UserDefaults(suiteName: getFileName())
    }

    init(siteId: SiteId, deviceMetricsGrabber: DeviceMetricsGrabber) {
        self.siteId = siteId
        self.deviceMetricsGrabber = deviceMetricsGrabber
    }

    // Used for global data that's relevant to *all* of the site-ids (not sandboxed).
    // Instead of the more common way the SDK stores data by sandboxing all of that data by site-id.
    // See `GlobalDataStore` for data that is relevant for *all* site-ids in the SDK.
    public func switchToGlobalDataStore() {
        siteId = nil
    }

    /**
     We want to sandbox all of the data for each CIO workspace and app.
     Therefore, we use the app's bundle ID to be unique to the app and the siteId to separate all of the sites.

     We also need to have 1 set of UserPreferences that all workspaces of an app share.
     For these moments, use `shared` as the `siteId` value.
     */
    internal func getFileName() -> String {
        var appUniqueIdentifier = ""
        if let appBundleId = deviceMetricsGrabber.appBundleId {
            appUniqueIdentifier = ".\(appBundleId)"
        }

        var siteIdPart = ".shared" // used for storing global data used for all site-ids.
        if let siteId = siteId { // if a siteid is given to this instance, we dont store global data with this instance.
            siteIdPart = ".\(siteId)"
        }

        return "io.customer.sdk\(appUniqueIdentifier)\(siteIdPart)"
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

    public func deleteAll() {
        userDefaults?.deleteAll()
    }
}
