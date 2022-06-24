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
    // HTTP requests can be paused to avoid spamming the API too hard.
    // This Date is when a pause is able to be lifted.
    var httpRequestsPauseEnds: Date? { get set }
    // keep track of the last viewed screen that was tracked to prevent sending duplicates.
    var lastTrackedScreenName: String? { get set }
}

// Note: using singleton because we are storing some properties use in-memory as storage mechanism.
// sourcery: InjectRegister = "GlobalDataStore"
// sourcery: InjectSingleton
public class CioGlobalDataStore: GlobalDataStore {
    private var diGraph: DICommon {
        // Used *only* for information that needs to be global between all site ids!
        DICommon.getAllWorkspacesSharedInstance()
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

    public var httpRequestsPauseEnds: Date? {
        get {
            keyValueStorage.date(.httpRequestsPauseEnds)
        }
        set {
            keyValueStorage.setDate(newValue, forKey: .httpRequestsPauseEnds)
        }
    }

    // have this value in-memory so that it gets automatically cleared after the app gets cleared from memory.
    // When app restarts, we don't want to know the last tracked screen so we can track the first screen that's seen when the app opens.
    public var lastTrackedScreenName: String?

    public init() {}

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
