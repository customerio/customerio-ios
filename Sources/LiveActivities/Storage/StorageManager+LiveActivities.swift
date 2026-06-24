import CioInternalCommon
import Foundation

extension StorageManager {
    func getLiveActivityPushToken(activityType: String) throws -> String? {
        try db.fetchOne(LiveActivityTokenRecord.self, id: activityType)?.tokenHex
    }

    func setLiveActivityPushToken(activityType: String, tokenHex: String) throws {
        _ = try db.save(LiveActivityTokenRecord(activityType: activityType, tokenHex: tokenHex))
    }

    func clearAllLiveActivityPushTokens() throws {
        _ = try db.execute("DELETE FROM live_activity_push_tokens")
    }
}

// MARK: - Entity Record

private struct LiveActivityTokenRecord: Entity {
    static let tableName = TableName("live_activity_push_tokens")
    static let primaryKeyName = "activityType"
    static let primaryKey: WritableKeyPath<LiveActivityTokenRecord, String> & Sendable = \.activityType

    var activityType: String
    var tokenHex: String
}
