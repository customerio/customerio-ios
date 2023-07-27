import Foundation

/**
 The keys for `KeyValueStorage`. Less error-prone then hard-coded strings.
 */
public enum KeyValueStorageKey: String, CaseIterable {
    case identifiedProfileId
    case pushDeviceToken
    case httpRequestsPauseEnds
    case migrationsRun
}
