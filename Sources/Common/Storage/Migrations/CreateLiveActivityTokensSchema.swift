import Foundation
@preconcurrency import SyncSqlCipher

// MARK: - Schema

/// Migration that creates the live activity push-to-start registration table.
/// Referenced by `StorageManager.runMigrations()`.
///
/// Stores one row per activity type holding the last `"<pushToStartToken>|<userId>"`
/// signature registered with the backend, so unchanged token+user pairs are not
/// re-registered on every launch. Supersedes the earlier `live_activity_push_tokens`
/// table (dropped here) which keyed only on the raw token.
struct CreateLiveActivityTokensSchema: Migration {
    let id = "la-002-create-pts-registration-signatures"

    func up(_ ctx: MigrationContext) throws {
        // Drop the pre-signature table if a previous build created it.
        try ctx.execute("DROP TABLE IF EXISTS live_activity_push_tokens")
        try ctx.execute(
            """
            CREATE TABLE IF NOT EXISTS live_activity_pts_registrations (
                activityType TEXT NOT NULL PRIMARY KEY,
                signature    TEXT NOT NULL
            )
            """
        )
    }

    func down(_ ctx: MigrationContext) throws {}
}
