import Foundation

/// SDK data that is common between all site ids.
public protocol GlobalDataStore: AutoMockable {
    // site id used for the singleton instance of the SDK.
    var sharedInstanceSiteId: String? { get set }
    func appendSiteId(_ siteId: String)
    // all site ids that have ever been registered with the SDK
    var siteIds: [String] { get }
    // APN or FCM device token
    var pushDeviceToken: String? { get set }
}

// sourcery: InjectRegister = "GlobalDataStore"
public class CioGlobalDataStore: GlobalDataStore {
    private var diGraph: DITracking {
        // Used *only* for information that needs to be global between all site ids!
        DITracking.getAllWorkspacesSharedInstance()
    }

    internal var keyValueStorage: KeyValueStorage {
        diGraph.keyValueStorage
    }

    public var sharedInstanceSiteId: String? {
        get {
            keyValueStorage.string(.sharedInstanceSiteId)
        }
        set {
            keyValueStorage.setString(newValue, forKey: .sharedInstanceSiteId)
        }
    }

    public var pushDeviceToken: String? {
        get {
            keyValueStorage.string(.pushDeviceToken)
        }
        set {
            keyValueStorage.setString(newValue, forKey: .pushDeviceToken)
        }
    }

    /**
     Save all of the site ids given to the SDK. We are storing this because we may need to iterate all of the
     site ids in the future so let's capture them now so we have them.
     */
    public func appendSiteId(_ siteId: String) {
        let existingSiteIds = keyValueStorage.string(.allSiteIds) ?? ""

        // Must convert String.Substring to String which is why we map()
        var allSiteIds = Set(existingSiteIds.split(separator: ",").map { String($0) })

        allSiteIds.insert(siteId)

        let newSiteIds = allSiteIds.joined(separator: ",")

        keyValueStorage.setString(newSiteIds, forKey: .allSiteIds)
    }

    public var siteIds: [String] {
        guard let allSiteIds = keyValueStorage.string(.allSiteIds) else {
            return []
        }

        return allSiteIds.split(separator: ",").map { String($0) }
    }
}
