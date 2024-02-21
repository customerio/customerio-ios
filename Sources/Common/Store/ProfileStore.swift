import Foundation

public protocol ProfileStore: AutoMockable {
    func getProfileId(siteId: String) -> String?
    func deleteProfileId(siteId: String)
}

// sourcery: InjectRegisterShared = "ProfileStore"
public class CioProfileStore: ProfileStore {
    private let keyValueStorage: SandboxedSiteIdKeyValueStorage

    init(keyValueStorage: SandboxedSiteIdKeyValueStorage) {
        self.keyValueStorage = keyValueStorage
    }

    public func getProfileId(siteId: String) -> String? {
        keyValueStorage.string(.identifiedProfileId, siteId: siteId)
    }

    public func deleteProfileId(siteId: String) {
        keyValueStorage.setString(nil, forKey: .identifiedProfileId, siteId: siteId)
    }
}
