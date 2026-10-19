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

        // The SDK set up by `UnitTest` saves its own key as the last key used.
        UserDefaults.standard.removeObject(forKey: "io.customer.sdk.analyticsWriteKey")
        eventsDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: eventsDirectory)
        for key in usedKeys {
            UserDefaults.standard.removePersistentDomain(forName: "com.segment.storage.\(key)")
            Analytics.removeActiveWriteKey(key)
            UserDefaults.standard.removeObject(forKey: "io.customer.sdk.analyticsPendingEventsFrom.\(key)")
        }
        UserDefaults.standard.removeObject(forKey: "io.customer.sdk.analyticsWriteKey")

        super.tearDown()
    }

    func test_migrate_givenPublicKey_expectIdentityAndQueuedEventsCarryOver() {
        let oldKey = givenKey(String.random)
        let newKey = givenKey("pk_us_\(String.random)")
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

    func test_migrate_givenFinishedBatch_expectNewKeyAndSamePayloadAfterOldKeyRetired() throws {
        let oldKey = givenKey(String.random)
        let newKey = givenKey("pk_us_\(String.random)")
        givenIdentity(writeKey: oldKey, anonymousId: "anon-1")
        // Same name and shape analytics uses for a finished batch waiting to upload.
        let batch = #"{"batch":[{"type":"track","event":"queued","messageId":"msg-1"}],"sentAt":"2026-10-07T00:00:00.000Z","writeKey":"\#(oldKey)"}"#
        let file = eventsDirectory.appendingPathComponent(oldKey).appendingPathComponent("0-segment-events.temp")
        try batch.write(to: file, atomically: true, encoding: .utf8)

        migration().migrate(to: newKey)
        // Retire the old key: nothing left should still need it.
        Analytics.removeActiveWriteKey(oldKey)

        let newAnalytics = givenAnalytics(writeKey: newKey)
        let pending = try XCTUnwrap(newAnalytics.pendingUploads?.first { $0.lastPathComponent == file.lastPathComponent })
        let uploaded = try String(contentsOf: pending)
        XCTAssertEqual(uploaded, batch.replacingOccurrences(of: oldKey, with: newKey))
        XCTAssertFalse(uploaded.contains(oldKey))
    }

    func test_migrate_givenEventPropertyNamedWriteKey_expectOnlyBatchKeyChanged() throws {
        let oldKey = givenKey(String.random)
        let newKey = givenKey("pk_us_\(String.random)")
        givenIdentity(writeKey: oldKey, anonymousId: "anon-1")
        let event = #"{"type":"track","event":"queued","messageId":"msg-1","properties":{"writeKey":"\#(oldKey)"}}"#
        let batch = #"{"batch":[\#(event)],"sentAt":"2026-10-07T00:00:00.000Z","writeKey":"\#(oldKey)"}"#
        let file = eventsDirectory.appendingPathComponent(oldKey).appendingPathComponent("0-segment-events.temp")
        try batch.write(to: file, atomically: true, encoding: .utf8)

        migration().migrate(to: newKey)

        let newAnalytics = givenAnalytics(writeKey: newKey)
        let pending = try XCTUnwrap(newAnalytics.pendingUploads?.first { $0.lastPathComponent == file.lastPathComponent })
        let uploaded = try String(contentsOf: pending)
        XCTAssertEqual(uploaded, #"{"batch":[\#(event)],"sentAt":"2026-10-07T00:00:00.000Z","writeKey":"\#(newKey)"}"#)
    }

    func test_migrate_givenPublicKey_expectOldStorageRemoved() {
        let oldKey = givenKey(String.random)
        let newKey = givenKey("pk_us_\(String.random)")
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
        let newKey = givenKey("pk_us_\(String.random)")
        givenIdentity(writeKey: oldKey, anonymousId: "anon-old")
        givenIdentity(writeKey: newKey, anonymousId: "anon-new")

        migration().migrate(to: newKey)

        XCTAssertEqual(anonymousId(writeKey: newKey), "anon-new")
        XCTAssertEqual(anonymousId(writeKey: oldKey), "anon-old")
    }

    func test_migrate_givenSeveralOldKeys_expectMostRecentlyUsedMoved() throws {
        let olderKey = givenKey(String.random)
        let recentKey = givenKey(String.random)
        let newKey = givenKey("pk_eu_\(String.random)")
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

    func test_migrate_givenLastKeyHasNoEventsFolder_expectIdentityCarriesOver() throws {
        let oldKey = givenKey(String.random)
        let newKey = givenKey("pk_us_\(String.random)")
        migration().migrate(to: oldKey)
        givenIdentity(writeKey: oldKey, anonymousId: "anon-1")
        try FileManager.default.removeItem(at: eventsDirectory.appendingPathComponent(oldKey))

        migration().migrate(to: newKey)

        XCTAssertEqual(anonymousId(writeKey: newKey), "anon-1")
    }

    func test_migrate_givenEventsFailToMove_expectRetriedOnNextLaunch() throws {
        let oldKey = givenKey(String.random)
        let newKey = givenKey("pk_us_\(String.random)")
        givenIdentity(writeKey: oldKey, anonymousId: "anon-1")
        let queuedFile = givenQueuedEventsFile(writeKey: oldKey)
        // A file where the new events folder should be makes the move fail.
        let newDirectory = eventsDirectory.appendingPathComponent(newKey)
        try Data().write(to: newDirectory)

        migration().migrate(to: newKey)

        XCTAssertEqual(anonymousId(writeKey: newKey), "anon-1")
        XCTAssertTrue(FileManager.default.fileExists(atPath: queuedFile.path))

        try FileManager.default.removeItem(at: newDirectory)
        migration().migrate(to: newKey)

        XCTAssertTrue(FileManager.default.fileExists(atPath: newDirectory.appendingPathComponent(queuedFile.lastPathComponent).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: eventsDirectory.appendingPathComponent(oldKey).path))
    }

    func test_migrate_givenFinishedBatchWithoutKeyField_expectLeftBehindAndRetried() throws {
        let oldKey = givenKey(String.random)
        let newKey = givenKey("pk_us_\(String.random)")
        givenIdentity(writeKey: oldKey, anonymousId: "anon-1")
        let goodFile = givenQueuedEventsFile(writeKey: oldKey)
        let badFile = eventsDirectory.appendingPathComponent(oldKey).appendingPathComponent("1-segment-events.temp")
        try #"{"batch":[]}"#.write(to: badFile, atomically: true, encoding: .utf8)
        let newDirectory = eventsDirectory.appendingPathComponent(newKey)

        migration().migrate(to: newKey)

        XCTAssertTrue(FileManager.default.fileExists(atPath: newDirectory.appendingPathComponent(goodFile.lastPathComponent).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: badFile.path))
        XCTAssertEqual(UserDefaults.standard.string(forKey: "io.customer.sdk.analyticsPendingEventsFrom.\(newKey)"), oldKey)

        try #"{"batch":[],"writeKey":"\#(oldKey)"}"#.write(to: badFile, atomically: true, encoding: .utf8)
        migration().migrate(to: newKey)

        let moved = try String(contentsOf: newDirectory.appendingPathComponent(badFile.lastPathComponent), encoding: .utf8)
        XCTAssertEqual(moved, #"{"batch":[],"writeKey":"\#(newKey)"}"#)
        XCTAssertFalse(FileManager.default.fileExists(atPath: eventsDirectory.appendingPathComponent(oldKey).path))
        XCTAssertNil(UserDefaults.standard.string(forKey: "io.customer.sdk.analyticsPendingEventsFrom.\(newKey)"))
    }

    func test_migrate_givenEarlierMoveUnfinishedAndKeySwitchedAgain_expectOriginalEventsMoved() throws {
        let originalKey = givenKey(String.random)
        let firstKey = givenKey("pk_us_\(String.random)")
        let secondKey = givenKey("pk_us_\(String.random)")
        givenIdentity(writeKey: originalKey, anonymousId: "anon-1")
        let queuedFile = givenQueuedEventsFile(writeKey: originalKey)
        // A file where the first key's events folder should be makes that move fail.
        let firstDirectory = eventsDirectory.appendingPathComponent(firstKey)
        try Data().write(to: firstDirectory)
        migration().migrate(to: firstKey)
        try FileManager.default.removeItem(at: firstDirectory)

        migration().migrate(to: secondKey)

        let moved = try String(contentsOf: eventsDirectory.appendingPathComponent(secondKey).appendingPathComponent(queuedFile.lastPathComponent), encoding: .utf8)
        XCTAssertEqual(moved, #"{"batch":[],"writeKey":"\#(secondKey)"}"#)
        XCTAssertEqual(anonymousId(writeKey: secondKey), "anon-1")
        XCTAssertFalse(FileManager.default.fileExists(atPath: eventsDirectory.appendingPathComponent(originalKey).path))
        XCTAssertNil(UserDefaults.standard.string(forKey: "io.customer.sdk.analyticsPendingEventsFrom.\(firstKey)"))
        XCTAssertNil(UserDefaults.standard.string(forKey: "io.customer.sdk.analyticsPendingEventsFrom.\(secondKey)"))
    }

    func test_migrate_givenEarlierMoveUnfinishedAndSameBatchNames_expectAllBatchesMoved() throws {
        let originalKey = givenKey(String.random)
        let firstKey = givenKey("pk_us_\(String.random)")
        let secondKey = givenKey("pk_us_\(String.random)")
        givenIdentity(writeKey: originalKey, anonymousId: "anon-1")
        _ = givenQueuedEventsFile(writeKey: originalKey)
        let firstDirectory = eventsDirectory.appendingPathComponent(firstKey)
        try Data().write(to: firstDirectory)
        migration().migrate(to: firstKey)
        try FileManager.default.removeItem(at: firstDirectory)
        // The first key queued its own batch under the same name before switching again.
        try FileManager.default.createDirectory(at: firstDirectory, withIntermediateDirectories: true)
        _ = givenQueuedEventsFile(writeKey: firstKey)

        migration().migrate(to: secondKey)

        let secondDirectory = eventsDirectory.appendingPathComponent(secondKey)
        let moved = try FileManager.default.contentsOfDirectory(at: secondDirectory, includingPropertiesForKeys: nil)
            .map { try String(contentsOf: $0, encoding: .utf8) }
        XCTAssertEqual(moved, Array(repeating: #"{"batch":[],"writeKey":"\#(secondKey)"}"#, count: 2))
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstDirectory.path))
        XCTAssertNil(UserDefaults.standard.string(forKey: "io.customer.sdk.analyticsPendingEventsFrom.\(secondKey)"))
    }

    func test_migrate_givenNoPreviousKey_expectNothingMoved() {
        let newKey = givenKey("pk_us_\(String.random)")

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
