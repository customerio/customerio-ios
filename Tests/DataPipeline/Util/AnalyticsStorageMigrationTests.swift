@testable import CioAnalytics
@testable import CioDataPipelines
@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class AnalyticsStorageMigrationTests: UnitTest {
    private var eventsDirectory: URL!
    private var usedKeys: [String] = []
    private let queue = DispatchQueue(label: "AnalyticsStorageMigrationTests")

    override func setUp() {
        super.setUp()

        // The SDK set up by `UnitTest` records its own key as used.
        UserDefaults.standard.removeObject(forKey: "io.customer.sdk.analyticsWriteKeys")
        eventsDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: eventsDirectory)
        for key in usedKeys {
            UserDefaults.standard.removePersistentDomain(forName: "com.segment.storage.\(key)")
            Analytics.removeActiveWriteKey(key)
        }
        UserDefaults.standard.removeObject(forKey: "io.customer.sdk.analyticsWriteKeys")

        super.tearDown()
    }

    // MARK: identity

    func test_copyIdentity_givenPublicKey_expectIdentityCopiedAndOldKept() {
        let oldKey = givenKey(String.random)
        let newKey = givenKey("pk_us_\(String.random)")
        let identity: [String: Any] = ["segment.anonymousId": "anon-1", "segment.userId": "user-1", "segment.traits": Data([1, 2])]
        givenStorage(writeKey: oldKey, values: identity.merging(["segment.settings": "old settings"]) { $1 })
        givenLastKey(oldKey)

        XCTAssertTrue(migration().copyIdentity(to: newKey))

        let newValues = storedValues(writeKey: newKey)
        XCTAssertEqual(newValues["segment.anonymousId"] as? String, "anon-1")
        XCTAssertEqual(newValues["segment.userId"] as? String, "user-1")
        XCTAssertEqual(newValues["segment.traits"] as? Data, Data([1, 2]))
        XCTAssertNil(newValues["segment.settings"])
        let oldValues = storedValues(writeKey: oldKey)
        XCTAssertEqual(oldValues["segment.anonymousId"] as? String, "anon-1")
        XCTAssertEqual(oldValues["segment.userId"] as? String, "user-1")
    }

    func test_copyIdentity_givenRealAnalyticsIdentity_expectNewAnalyticsStartsWithIt() {
        let oldKey = givenKey(String.random)
        let newKey = givenKey("pk_us_\(String.random)")
        let oldAnalytics = givenAnalytics(writeKey: oldKey)
        oldAnalytics.identify(userId: "user-1")
        // analytics writes identity to disk asynchronously
        let userIdStored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            UserDefaults(suiteName: "com.segment.storage.\(oldKey)")?.string(forKey: "segment.userId") == "user-1"
        }, object: nil)
        wait(for: [userIdStored], timeout: 5)
        givenLastKey(oldKey)

        _ = migration().copyIdentity(to: newKey)

        let newAnalytics = givenAnalytics(writeKey: newKey)
        XCTAssertEqual(newAnalytics.anonymousId, oldAnalytics.anonymousId)
        XCTAssertEqual(newAnalytics.userId, "user-1")
    }

    func test_copyIdentity_givenNewKeyHasIdentity_expectNotOverwritten() {
        let oldKey = givenKey(String.random)
        let newKey = givenKey("pk_us_\(String.random)")
        givenStorage(writeKey: oldKey, values: ["segment.anonymousId": "anon-old", "segment.userId": "user-old"])
        givenStorage(writeKey: newKey, values: ["segment.anonymousId": "anon-new"])
        givenLastKey(oldKey)

        XCTAssertTrue(migration().copyIdentity(to: newKey))

        let newValues = storedValues(writeKey: newKey)
        XCTAssertEqual(newValues["segment.anonymousId"] as? String, "anon-new")
        XCTAssertNil(newValues["segment.userId"])
    }

    // Apps can also run Segment's own SDK with the same storage names, so storage this SDK didn't use is left alone.
    func test_copyIdentity_givenStorageFromKeyThisSdkNeverUsed_expectNothingCopied() {
        let segmentKey = givenKey(String.random)
        let newKey = givenKey("pk_us_\(String.random)")
        givenStorage(writeKey: segmentKey, values: ["segment.anonymousId": "anon-segment"])

        XCTAssertFalse(migration().copyIdentity(to: newKey))

        XCTAssertNil(UserDefaults.standard.persistentDomain(forName: "com.segment.storage.\(newKey)"))
    }

    func test_copyIdentity_givenKeyUnchanged_expectNothingHappens() {
        let key = givenKey("pk_us_\(String.random)")
        let otherKey = givenKey(String.random)
        givenStorage(writeKey: otherKey, values: ["segment.anonymousId": "anon-other"])
        givenStorage(writeKey: key, values: ["segment.userId": "user-1"])
        givenLastKey(key)

        // false means queued events aren't moved either
        XCTAssertFalse(migration().copyIdentity(to: key))

        XCTAssertEqual(storedValues(writeKey: key) as NSDictionary, ["segment.userId": "user-1"])
    }

    func test_copyIdentity_givenLegacyKey_expectNothingHappens() {
        let oldKey = givenKey(String.random)
        let newKey = givenKey(String.random)
        givenStorage(writeKey: oldKey, values: ["segment.anonymousId": "anon-1"])
        givenLastKey(oldKey)

        XCTAssertFalse(migration().copyIdentity(to: newKey))

        XCTAssertNil(UserDefaults.standard.persistentDomain(forName: "com.segment.storage.\(newKey)"))
    }

    func test_copyIdentity_givenNoPreviousKey_expectNothingHappens() {
        let newKey = givenKey("pk_us_\(String.random)")

        XCTAssertFalse(migration().copyIdentity(to: newKey))

        XCTAssertNil(UserDefaults.standard.persistentDomain(forName: "com.segment.storage.\(newKey)"))
    }

    // MARK: queued events

    func test_moveQueuedEvents_givenFinishedBatch_expectMovedUnchangedAndQueuedForUpload() throws {
        let oldKey = givenKey(String.random)
        let newKey = givenKey("pk_us_\(String.random)")
        let batch = try givenFinishedBatch(writeKey: oldKey)
        let contents = try String(contentsOf: batch, encoding: .utf8)
        // The new key already has a batch with the same name.
        let newKeyBatch = try givenFinishedBatch(writeKey: newKey)
        moveQueuedEvents(to: newKey, from: [oldKey])

        let analytics = givenAnalytics(writeKey: newKey)

        let moved = eventsDirectory.appendingPathComponent(newKey).appendingPathComponent("\(oldKey)-\(batch.lastPathComponent)")
        XCTAssertEqual(try String(contentsOf: moved, encoding: .utf8), contents)
        XCTAssertFalse(FileManager.default.fileExists(atPath: batch.path))
        XCTAssertEqual(
            Set(analytics.pendingUploads?.map(\.lastPathComponent) ?? []),
            [moved.lastPathComponent, newKeyBatch.lastPathComponent]
        )
    }

    func test_moveQueuedEvents_givenUnfinishedBatch_expectEventsAddedAsQueuedAndFileDeleted() throws {
        let oldKey = givenKey(String.random)
        let newKey = givenKey("pk_us_\(String.random)")
        let events = [
            #"{"type":"track","event":"first","messageId":"msg-1","timestamp":"2026-10-07T00:00:00.000Z","userId":"user-1","anonymousId":"anon-1","properties":{"text":"has } and \" in it"}}"#,
            #"{"type":"identify","messageId":"msg-2","timestamp":"2026-10-07T00:00:01.000Z","userId":"user-1","anonymousId":"anon-1","traits":{"n":1}}"#
        ]
        let file = try givenUnfinishedBatch(writeKey: oldKey, contents: unfinishedBatch(events))
        moveQueuedEvents(to: newKey, from: [oldKey])

        let analytics = givenAnalytics(writeKey: newKey)

        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(try uploadedEvents(analytics), try events.map(jsonObject))
        let batch = try String(contentsOf: XCTUnwrap(analytics.pendingUploads?.first), encoding: .utf8)
        XCTAssertTrue(batch.hasSuffix(#""writeKey":"\#(newKey)"}"#))
        events.forEach { XCTAssertTrue(batch.contains($0)) }
    }

    func test_moveQueuedEvents_givenCutOffLastEvent_expectItDropped() throws {
        let oldKey = givenKey(String.random)
        let newKey = givenKey("pk_us_\(String.random)")
        let complete = #"{"type":"track","event":"first","messageId":"msg-1"}"#
        let contents = unfinishedBatch([complete]) + #",{"type":"track","event":"sec"#
        let file = try givenUnfinishedBatch(writeKey: oldKey, contents: contents)
        moveQueuedEvents(to: newKey, from: [oldKey])

        let analytics = givenAnalytics(writeKey: newKey)

        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(try uploadedEvents(analytics), try [jsonObject(complete)])
    }

    func test_moveQueuedEvents_givenUnknownFormat_expectFileKept() throws {
        let oldKey = givenKey(String.random)
        let newKey = givenKey("pk_us_\(String.random)")
        let file = try givenUnfinishedBatch(writeKey: oldKey, contents: #"[{"type":"track","messageId":"msg-1"}]"#)
        moveQueuedEvents(to: newKey, from: [oldKey])

        let analytics = givenAnalytics(writeKey: newKey)

        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertNil(analytics.pendingUploads)
    }

    func test_moveQueuedEvents_givenUnfinishedBatchesFromSeveralEarlierKeys_expectAllAdded() throws {
        let firstKey = givenKey(String.random)
        let secondKey = givenKey("pk_us_\(String.random)")
        let newKey = givenKey("pk_us_\(String.random)")
        let firstEvent = #"{"type":"track","event":"first","messageId":"msg-1"}"#
        let secondEvent = #"{"type":"track","event":"second","messageId":"msg-2"}"#
        _ = try givenUnfinishedBatch(writeKey: firstKey, contents: unfinishedBatch([firstEvent]))
        _ = try givenUnfinishedBatch(writeKey: secondKey, contents: unfinishedBatch([secondEvent]))
        moveQueuedEvents(to: newKey, from: [firstKey, secondKey])

        let analytics = givenAnalytics(writeKey: newKey)

        let messageIds = try uploadedEvents(analytics).compactMap { $0["messageId"] as? String }
        XCTAssertEqual(Set(messageIds), ["msg-1", "msg-2"])
    }

    func test_moveQueuedEvents_givenFolderOfKeyThisSdkNeverUsed_expectLeftAlone() throws {
        let oldKey = givenKey(String.random)
        let segmentKey = givenKey(String.random)
        let newKey = givenKey("pk_us_\(String.random)")
        let segmentBatch = try givenFinishedBatch(writeKey: segmentKey)
        let segmentUnfinished = try givenUnfinishedBatch(writeKey: segmentKey, contents: unfinishedBatch([#"{"messageId":"msg-1"}"#]))

        moveQueuedEvents(to: newKey, from: [oldKey])

        XCTAssertTrue(FileManager.default.fileExists(atPath: segmentBatch.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: segmentUnfinished.path))
        XCTAssertNil(givenAnalytics(writeKey: newKey).pendingUploads)
    }
}

private extension AnalyticsStorageMigrationTests {
    func migration() -> AnalyticsStorageMigration {
        AnalyticsStorageMigration(logger: log, eventsDirectory: eventsDirectory)
    }

    func moveQueuedEvents(to newKey: String, from earlierKeys: [String]) {
        UserDefaults.standard.set(earlierKeys + [newKey], forKey: "io.customer.sdk.analyticsWriteKeys")
        migration().moveQueuedEvents(to: newKey, on: queue)
        queue.sync {}
    }

    func givenKey(_ key: String) -> String {
        usedKeys.append(key)
        return key
    }

    func givenLastKey(_ key: String) {
        UserDefaults.standard.set([key], forKey: "io.customer.sdk.analyticsWriteKeys")
    }

    func givenAnalytics(writeKey: String) -> Analytics {
        let configuration = Configuration(writeKey: writeKey)
            .storageMode(.diskAtURL(eventsDirectory.appendingPathComponent(writeKey)))
            .trackApplicationLifecycleEvents(false)
            .autoAddSegmentDestination(false)
            .flushPolicies([])
        let analytics = Analytics(configuration: configuration)
        analytics.waitUntilStarted()
        return analytics
    }

    /// Stores analytics values and an events directory for `writeKey`, as analytics does after running with it.
    func givenStorage(writeKey: String, values: [String: Any]) {
        UserDefaults.standard.setPersistentDomain(values, forName: "com.segment.storage.\(writeKey)")
        try? FileManager.default.createDirectory(at: eventsDirectory.appendingPathComponent(writeKey), withIntermediateDirectories: true)
    }

    func storedValues(writeKey: String) -> [String: Any] {
        UserDefaults.standard.persistentDomain(forName: "com.segment.storage.\(writeKey)") ?? [:]
    }

    /// Same name and shape analytics uses for a finished batch waiting to upload.
    func givenFinishedBatch(writeKey: String) throws -> URL {
        let batch = #"{"batch":[{"type":"track","event":"queued","messageId":"msg-\#(writeKey)"}],"sentAt":"2026-10-07T00:00:00.000Z","writeKey":"\#(writeKey)"}"#
        return try givenFile(writeKey: writeKey, name: "0-segment-events.temp", contents: batch)
    }

    func givenUnfinishedBatch(writeKey: String, contents: String) throws -> URL {
        try givenFile(writeKey: writeKey, name: "3-segment-events", contents: contents)
    }

    func givenFile(writeKey: String, name: String, contents: String) throws -> URL {
        let directory = eventsDirectory.appendingPathComponent(writeKey)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(name)
        try contents.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    /// Same shape analytics writes while a batch is still open.
    func unfinishedBatch(_ events: [String]) -> String {
        "{ \"batch\": [\n" + events.joined(separator: "\n,") + "\n"
    }

    func jsonObject(_ string: String) throws -> NSDictionary {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(string.utf8)) as? NSDictionary)
    }

    /// Events in the batches analytics would upload for the new key.
    func uploadedEvents(_ analytics: Analytics) throws -> [NSDictionary] {
        try (analytics.pendingUploads ?? []).flatMap { file -> [NSDictionary] in
            let batch = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            return try XCTUnwrap(batch["batch"] as? [NSDictionary])
        }
    }
}
