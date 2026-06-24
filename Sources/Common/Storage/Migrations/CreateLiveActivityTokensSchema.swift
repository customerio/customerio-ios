import Foundation
@preconcurrency import SyncSqlCipher

// MARK: - Schema

/// Migration that creates the live activity push-to-start token table.
/// Referenced by `StorageManager.runMigrations()`.
struct CreateLiveActivityTokensSchema: Migration {
    let id = "la-001-create-live-activity-push-tokens"

    func up(_ ctx: MigrationContext) throws {
        try ctx.execute(
            """
            CREATE TABLE IF NOT EXISTS live_activity_push_tokens (
                activityType TEXT NOT NULL PRIMARY KEY,
                tokenHex     TEXT NOT NULL
            )
            """
        )
    }

    func down(_ ctx: MigrationContext) throws {}
}
