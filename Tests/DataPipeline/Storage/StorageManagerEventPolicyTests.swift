@testable import CioDataPipelines
import CioInternalCommon
import SyncSqlCipher
import Testing

@Suite("StorageManager rate-limit storage")
struct StorageManagerEventPolicyTests {
    let storage: StorageManager

    init() throws {
        let db = try Database(path: ":memory:", key: "testkey", walMode: false)
        self.storage = StorageManager(db: db)
        try storage.runMigrations()
    }

    // MARK: - First call always passes

    @Test func firstCall_returnsTrue() throws {
        let result = try storage.checkAndUpdateRateLimit(
            key: "track:button_clicked",
            now: 1000,
            windowSeconds: 3600,
            scope: "profile"
        )
        #expect(result == true)
    }

    // MARK: - Within window is blocked

    @Test func secondCallWithinWindow_returnsFalse() throws {
        let key = "track:button_clicked"
        _ = try storage.checkAndUpdateRateLimit(key: key, now: 1000, windowSeconds: 3600, scope: "profile")
        let result = try storage.checkAndUpdateRateLimit(key: key, now: 1001, windowSeconds: 3600, scope: "profile")
        #expect(result == false)
    }

    // MARK: - After window passes through

    @Test func callAfterWindowExpiry_returnsTrue() throws {
        let key = "track:button_clicked"
        _ = try storage.checkAndUpdateRateLimit(key: key, now: 1000, windowSeconds: 3600, scope: "profile")
        let result = try storage.checkAndUpdateRateLimit(key: key, now: 1000 + 3600 + 1, windowSeconds: 3600, scope: "profile")
        #expect(result == true)
    }

    // MARK: - Different keys are isolated

    @Test func differentKeys_areIsolated() throws {
        _ = try storage.checkAndUpdateRateLimit(key: "track:a", now: 1000, windowSeconds: 3600, scope: "profile")
        _ = try storage.checkAndUpdateRateLimit(key: "track:b", now: 1000, windowSeconds: 3600, scope: "profile")

        let aBlocked = try storage.checkAndUpdateRateLimit(key: "track:a", now: 2000, windowSeconds: 3600, scope: "profile")
        let bBlocked = try storage.checkAndUpdateRateLimit(key: "track:b", now: 2000, windowSeconds: 3600, scope: "profile")

        #expect(aBlocked == false)
        #expect(bBlocked == false)
    }

    // MARK: - Timestamp is updated after window

    @Test func afterWindowExpiry_timestampUpdates_newWindowApplied() throws {
        let key = "track:ev"
        _ = try storage.checkAndUpdateRateLimit(key: key, now: 1000, windowSeconds: 100, scope: "profile")
        _ = try storage.checkAndUpdateRateLimit(key: key, now: 1101, windowSeconds: 100, scope: "profile") // passes, resets clock

        // New window starts from 1_101; calling at 1_150 should be blocked
        let result = try storage.checkAndUpdateRateLimit(key: key, now: 1150, windowSeconds: 100, scope: "profile")
        #expect(result == false)
    }
}
