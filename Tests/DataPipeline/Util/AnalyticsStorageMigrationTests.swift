@testable import CioAnalytics
@testable import CioDataPipelines
@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class AnalyticsStorageMigrationTests: UnitTest {
    private var eventsDirectory: URL!
    private var usedKeys: [String] = []

    override func setUp() {
        super.setUp()

        eventsDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: eventsDirectory)
        for key in usedKeys {
            UserDefaults.standard.removePersistentDomain(forName: "com.segment.storage.\(key)")
            Analytics.removeActiveWriteKey(key)
        }

        super.tearDown()
    }

    func test_migrate_givenPublicKey_expectIdentityAndQueuedEventsCarryOver() {
        let oldKey = givenKey(String.random)
        let newKey = givenKey("wk_us_\(String.random)")
        let oldAnalytics = givenAnalytics(writeKey: oldKey)
        oldAnalytics.identify(userId: "user-1")
        // analytics writes identity to disk asynchronously
        let userIdStored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            UserDefaults(suiteName: "com.segment.storage.\(oldKey)")?.string(forKey: "segment.userId") == "user-1"
        }, object: nil)
        wait(for: [userIdStored], timeout: 5)
        let anonymousId = oldAnalytics.anonymousId
        let queuedFile = givenQueuedEventsFile(writeKey: oldKey)

        migration().migrate(to: newKey)

        let newAnalytics = givenAnalytics(writeKey: newKey)
        XCTAssertEqual(newAnalytics.anonymousId, anonymousId)
        XCTAssertEqual(newAnalytics.userId, "user-1")
        XCTAssertEqual(newAnalytics.pendingUploads?.map(\.lastPathComponent), [queuedFile.lastPathComponent])
    }

    func test_migrate_givenPublicKey_expectOldStorageRemoved() {
        let oldKey = givenKey(String.random)
        let newKey = givenKey("wk_us_\(String.random)")
        givenIdentity(writeKey: oldKey, anonymousId: "anon-1")

        migration().migrate(to: newKey)

        XCTAssertEqual(anonymousId(writeKey: newKey), "anon-1")
        XCTAssertNil(UserDefaults.standard.persistentDomain(forName: "com.segment.storage.\(oldKey)"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: eventsDirectory.appendingPathComponent(oldKey).path))
    }

    func test_migrate_givenLegacyKey_expectNothingMoved() {
        let oldKey = givenKey(String.random)
        let newKey = givenKey(String.random)
        givenIdentity(writeKey: oldKey, anonymousId: "anon-1")

        migration().migrate(to: newKey)

        XCTAssertNil(UserDefaults.standard.persistentDomain(forName: "com.segment.storage.\(newKey)"))
        XCTAssertNotNil(UserDefaults.standard.persistentDomain(forName: "com.segment.storage.\(oldKey)"))
    }

    func test_migrate_givenNewKeyAlreadyHasIdentity_expectNothingMoved() {
        let oldKey = givenKey(String.random)
        let newKey = givenKey("wk_us_\(String.random)")
        givenIdentity(writeKey: oldKey, anonymousId: "anon-old")
        givenIdentity(writeKey: newKey, anonymousId: "anon-new")

        migration().migrate(to: newKey)

        XCTAssertEqual(anonymousId(writeKey: newKey), "anon-new")
        XCTAssertEqual(anonymousId(writeKey: oldKey), "anon-old")
    }

    func test_migrate_givenSeveralOldKeys_expectMostRecentlyUsedMoved() throws {
        let olderKey = givenKey(String.random)
        let recentKey = givenKey(String.random)
        let newKey = givenKey("wk_eu_\(String.random)")
        givenIdentity(writeKey: olderKey, anonymousId: "anon-older")
        givenIdentity(writeKey: recentKey, anonymousId: "anon-recent")
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -3600)],
            ofItemAtPath: eventsDirectory.appendingPathComponent(olderKey).path
        )

        migration().migrate(to: newKey)

        XCTAssertEqual(anonymousId(writeKey: newKey), "anon-recent")
        XCTAssertEqual(anonymousId(writeKey: olderKey), "anon-older")
    }

    func test_migrate_givenNoPreviousKey_expectNothingMoved() {
        let newKey = givenKey("wk_us_\(String.random)")

        migration().migrate(to: newKey)

        XCTAssertNil(UserDefaults.standard.persistentDomain(forName: "com.segment.storage.\(newKey)"))
    }
}

private extension AnalyticsStorageMigrationTests {
    func migration() -> AnalyticsStorageMigration {
        AnalyticsStorageMigration(logger: log, eventsDirectory: eventsDirectory)
    }

    func givenKey(_ key: String) -> String {
        usedKeys.append(key)
        return key
    }

    func givenAnalytics(writeKey: String) -> Analytics {
        let configuration = Configuration(writeKey: writeKey)
            .storageMode(.diskAtURL(eventsDirectory.appendingPathComponent(writeKey)))
            .trackApplicationLifecycleEvents(false)
            .autoAddSegmentDestination(false)
        let analytics = Analytics(configuration: configuration)
        analytics.waitUntilStarted()
        return analytics
    }

    /// Stores identity and an events directory for `writeKey`, as analytics does after running with it.
    func givenIdentity(writeKey: String, anonymousId: String) {
        UserDefaults.standard.setPersistentDomain(["segment.anonymousId": anonymousId], forName: "com.segment.storage.\(writeKey)")
        try? FileManager.default.createDirectory(
            at: eventsDirectory.appendingPathComponent(writeKey),
            withIntermediateDirectories: true
        )
    }

    func anonymousId(writeKey: String) -> String? {
        UserDefaults.standard.persistentDomain(forName: "com.segment.storage.\(writeKey)")?["segment.anonymousId"] as? String
    }

    func givenQueuedEventsFile(writeKey: String) -> URL {
        let file = eventsDirectory.appendingPathComponent(writeKey).appendingPathComponent("0-segment-events.temp")
        try? #"{"batch":[],"writeKey":"\#(writeKey)"}"#.write(to: file, atomically: true, encoding: .utf8)
        return file
    }
}
