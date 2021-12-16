import Foundation

public protocol GlobalDataStore {
    var sharedInstanceSiteId: String? { get set }
    func appendSiteId(_ siteId: String)
    var siteIds: [String] { get }
    var badgeCount : Int? {get set}
}
// sourcery: InjectRegister = "GlobalDataStore"
public class CioGlobalDataStore: GlobalDataStore {
    private var diGraph: DI {
        // Used *only* for information that needs to be global between all site ids!
        DI.getInstance(siteId: "shared")
    }

    internal var keyValueStorage: KeyValueStorage {
        diGraph.keyValueStorage
    }
    
    public init() {
        
    }

    public var sharedInstanceSiteId: String? {
        get {
            keyValueStorage.string(.sharedInstanceSiteId)
        }
        set {
            keyValueStorage.setString(newValue, forKey: .sharedInstanceSiteId)
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
    
    public var badgeCount: Int? {
        get {
            keyValueStorage.integer(.badgeCount)
        }
        set {
            keyValueStorage.setInt(newValue, forKey: .badgeCount)
        }
    }
}
