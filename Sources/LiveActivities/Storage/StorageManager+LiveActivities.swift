import CioInternalCommon
import Foundation

extension StorageManager {
    /// The last push-to-start registration signature (`"<token>|<userId>"`) sent for
    /// `activityType`, or `nil` if none has been recorded.
    func getRegistrationSignature(activityType: String) throws -> String? {
        try db.fetchOne(LiveActivityRegistrationRecord.self, id: activityType)?.signature
    }

    func setRegistrationSignature(activityType: String, signature: String) throws {
        _ = try db.save(LiveActivityRegistrationRecord(activityType: activityType, signature: signature))
    }

    func clearAllLiveActivityRegistrations() throws {
        _ = try db.execute("DELETE FROM live_activity_pts_registrations")
    }
}

// MARK: - Entity Record

private struct LiveActivityRegistrationRecord: Entity {
    static let tableName = TableName("live_activity_pts_registrations")
    static let primaryKeyName = "activityType"
    static let primaryKey: WritableKeyPath<LiveActivityRegistrationRecord, String> & Sendable = \.activityType

    var activityType: String
    var signature: String
}
