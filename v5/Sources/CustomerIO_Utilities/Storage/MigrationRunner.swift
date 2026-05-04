import Foundation
import SqlCipherKit

/// Runs a one-time migration from the legacy SDK on first launch after upgrade.
/// Sets `sdk_meta.legacy_migration_complete = true` when finished so it never
/// runs again.
public actor MigrationRunner {

    private let storage: StorageManager

    public init(storage: StorageManager) {
        self.storage = storage
    }

    /// Read legacy UserDefaults values and return them as seeds.
    ///
    /// Returns `nil` for each field if nothing was found. The caller is
    /// responsible for writing seeds into the appropriate stores.
    public nonisolated func legacySeeds() -> LegacySeeds {
        let defaults = UserDefaults.standard
        return LegacySeeds(
            profileId: defaults.string(forKey: "identifiedProfileId"),
            anonymousId: defaults.string(forKey: "CioAnalytics.anonymousId"),
            pushToken: defaults.string(forKey: "CioGlobalDataStore.pushToken")
        )
    }

    /// Mark legacy migration as complete so it is never re-attempted.
    public func markComplete() async throws {
        try await storage.setMetaValue("true", for: CIOKeys.Storage.legacyMigrationCompleteKey)
    }

    /// Whether the legacy migration has already been applied.
    public func isComplete() async -> Bool {
        (try? await storage.getMetaValue(CIOKeys.Storage.legacyMigrationCompleteKey)) == "true"
    }
}

// MARK: -

public struct LegacySeeds: Sendable {
    public let profileId: String?
    public let anonymousId: String?
    public let pushToken: String?
}
