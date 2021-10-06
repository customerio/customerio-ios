import Foundation

/**
 The keys for `KeyValueStorage`. Less error-prone then hard-coded strings.
 */
public enum KeyValueStorageKey: String {
    case sharedInstanceSiteId
    case apiKey
    case regionCode
    case identifiedProfileId
    case loggedOutProfileId
    case allSiteIds
}
