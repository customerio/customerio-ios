import Foundation
@preconcurrency import SyncSqlCipher

struct CreateSdkMetaSchema: Migration {
    let id = "001-create-sdk-meta"

    func up(_ ctx: MigrationContext) throws {
        try ctx.execute(
            """
            CREATE TABLE IF NOT EXISTS sdk_meta (
                key   TEXT NOT NULL PRIMARY KEY,
                value TEXT NOT NULL
            )
            """
        )
    }

    func down(_ ctx: MigrationContext) throws {}
}
