@testable import CioInternalCommon
import Foundation
import SharedTests
import Testing

@Suite("BackgroundDeliveryContextStore")
struct BackgroundDeliveryContextStoreTests {
    private func makeStore() -> (store: BackgroundDeliveryContextStore, directory: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = BackgroundDeliveryContextStore(fileManager: .default, directoryURL: directory)
        return (store, directory)
    }

    @Test
    func fields_givenNeverWritten_expectAllNil() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(store.currentUserId == nil)
        #expect(store.currentApiHost == nil)
        #expect(store.currentCdpApiKey == nil)
    }

    @Test
    func setters_givenValues_expectPersistedAndReadable() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        store.setUserId("user_42")
        store.setApiHost("cdp.customer.io/v1")
        store.setCdpApiKey("sk_test_abc")
        #expect(store.currentUserId == "user_42")
        #expect(store.currentApiHost == "cdp.customer.io/v1")
        #expect(store.currentCdpApiKey == "sk_test_abc")
    }

    @Test
    func setters_givenEmptyString_expectTreatedAsClear() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        store.setUserId("user_42")
        store.setApiHost("cdp.customer.io/v1")
        store.setCdpApiKey("sk_test_abc")
        store.setUserId("")
        store.setApiHost("")
        store.setCdpApiKey("")
        #expect(store.currentUserId == nil)
        #expect(store.currentApiHost == nil)
        #expect(store.currentCdpApiKey == nil)
    }

    @Test
    func setOneField_expectOthersUntouched() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        store.setUserId("user_42")
        store.setApiHost("cdp.customer.io/v1")
        store.setCdpApiKey("sk_test_abc")
        store.setApiHost("cdp-eu.customer.io/v1")
        #expect(store.currentUserId == "user_42")
        #expect(store.currentApiHost == "cdp-eu.customer.io/v1")
        #expect(store.currentCdpApiKey == "sk_test_abc")
    }

    @Test
    func reset_expectAllFieldsCleared() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        store.setUserId("user_42")
        store.setApiHost("cdp.customer.io/v1")
        store.setCdpApiKey("sk_test_abc")
        store.reset()
        #expect(store.currentUserId == nil)
        #expect(store.currentApiHost == nil)
        #expect(store.currentCdpApiKey == nil)
    }

    @Test
    func fields_givenNewStoreOnSameDirectory_expectLoadsPreviousValues() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = BackgroundDeliveryContextStore(fileManager: .default, directoryURL: directory)
        first.setUserId("user_42")
        first.setApiHost("cdp.customer.io/v1")
        first.setCdpApiKey("sk_test_abc")

        let reborn = BackgroundDeliveryContextStore(fileManager: .default, directoryURL: directory)
        #expect(reborn.currentUserId == "user_42")
        #expect(reborn.currentApiHost == "cdp.customer.io/v1")
        #expect(reborn.currentCdpApiKey == "sk_test_abc")
    }

    @Test
    func concurrentWrites_acrossFields_expectAllPersistedNoLostUpdates() async {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Fire writes to all three fields concurrently; without locking, the load-modify-write
        // sequence would race and some fields would end up nil.
        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 50 {
                group.addTask { store.setUserId("user_42") }
                group.addTask { store.setApiHost("cdp.customer.io/v1") }
                group.addTask { store.setCdpApiKey("sk_test_abc") }
            }
        }

        #expect(store.currentUserId == "user_42")
        #expect(store.currentApiHost == "cdp.customer.io/v1")
        #expect(store.currentCdpApiKey == "sk_test_abc")

        // Re-read via a fresh store to assert the on-disk state, not just the cache.
        let reloaded = BackgroundDeliveryContextStore(fileManager: .default, directoryURL: dir)
        #expect(reloaded.currentUserId == "user_42")
        #expect(reloaded.currentApiHost == "cdp.customer.io/v1")
        #expect(reloaded.currentCdpApiKey == "sk_test_abc")
    }

    // MARK: - cdpApiKey provider

    @Test
    func currentCdpApiKey_givenProviderRegistered_expectProviderValueWins() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        store.setCdpApiKey("persisted_key")
        let provider = StubCdpApiKeyProvider(value: "live_key")
        store.setCdpApiKeyProvider(provider)
        #expect(store.currentCdpApiKey == "live_key")
    }

    @Test
    func currentCdpApiKey_givenProviderNil_expectPersistedFallback() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        store.setCdpApiKey("persisted_key")
        #expect(store.currentCdpApiKey == "persisted_key")
    }

    @Test
    func currentCdpApiKey_givenProviderReturnsNil_expectPersistedFallback() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        store.setCdpApiKey("persisted_key")
        let provider = StubCdpApiKeyProvider(value: nil)
        store.setCdpApiKeyProvider(provider)
        #expect(store.currentCdpApiKey == "persisted_key")
    }

    @Test
    func currentCdpApiKey_givenProviderReturnsEmpty_expectPersistedFallback() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        store.setCdpApiKey("persisted_key")
        let provider = StubCdpApiKeyProvider(value: "")
        store.setCdpApiKeyProvider(provider)
        #expect(store.currentCdpApiKey == "persisted_key")
    }

    @Test
    func currentCdpApiKey_givenProviderDeallocated_expectPersistedFallback() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        store.setCdpApiKey("persisted_key")
        autoreleasepool {
            let provider = StubCdpApiKeyProvider(value: "live_key")
            store.setCdpApiKeyProvider(provider)
            #expect(store.currentCdpApiKey == "live_key")
        }
        // Provider was the only strong ref; after the autoreleasepool drains, the
        // weak ref inside the store should be nil and we fall back to disk.
        #expect(store.currentCdpApiKey == "persisted_key")
    }
}

/// The user-change notification other modules rely on to see identity changes as the producer
/// makes them, before any profile event is delivered.
@Suite("BackgroundDeliveryContextStore user changes")
struct ContextStoreUserChangeTests {
    private func makeStore() -> (store: BackgroundDeliveryContextStore, directory: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (BackgroundDeliveryContextStore(fileManager: .default, directoryURL: directory), directory)
    }

    /// Posted before the setter returns, with the new user; a clear posts no user.
    @Test
    func setUserId_givenAChange_expectNotifiedSynchronouslyInOrder() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let recorder = UserChangeRecorder(observing: store)

        store.setUserId("user-a")
        #expect(recorder.changes == ["user-a"])
        store.setUserId("user-b")
        store.setUserId("user-a")
        store.clearUserId()

        #expect(recorder.changes == ["user-a", "user-b", "user-a", nil])
    }

    /// A repeat, an empty string where none is stored, and other fields change no user.
    @Test
    func setUserId_givenNoRealChange_expectNoNotification() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let recorder = UserChangeRecorder(observing: store)

        store.setUserId("")
        store.setUserId(nil)
        store.setUserId("user-a")
        store.setUserId("user-a")
        store.setApiHost("cdp.customer.io/v1")
        store.setCdpApiKey("sk_test_abc")

        #expect(recorder.changes == ["user-a"])
    }

    /// An empty string where a user is stored is a clear, and so is a reset.
    @Test
    func clearingTheUser_givenEmptyStringOrReset_expectNotifiedAsCleared() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let recorder = UserChangeRecorder(observing: store)

        store.setUserId("user-a")
        store.setUserId("")
        store.setUserId("user-b")
        store.reset()

        #expect(recorder.changes == ["user-a", nil, "user-b", nil])
    }

    /// Scoped to the store posting it: another instance's changes reach no observer of this one.
    @Test
    func setUserId_givenAnotherStore_expectItsChangesNotSeen() {
        let (store, dir) = makeStore()
        let (other, otherDir) = makeStore()
        defer {
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.removeItem(at: otherDir)
        }
        let recorder = UserChangeRecorder(observing: store)

        other.setUserId("user-x")

        #expect(recorder.changes.isEmpty)
    }
}

/// The durable identity version: advanced by every real change of user, persisted with it, and
/// read by other modules through an internal snapshot request. Names are matched by their string
/// values, as another module matches them.
@Suite("BackgroundDeliveryContextStore identity version")
struct ContextStoreIdentityVersionTests {
    private static let snapshotRequest = Notification.Name("io.customer.sdk.BackgroundDeliveryContextStore.userSnapshotRequest")
    private static let changeNotification = Notification.Name("io.customer.sdk.BackgroundDeliveryContextStore.userIdDidChange")

    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func snapshot(of store: BackgroundDeliveryContextStore) -> (userId: String?, version: UInt64)? {
        var answer: (String?, UInt64)?
        let reply: (String?, UInt64, String) -> Void = { userId, version, _ in answer = (userId, version) }
        NotificationCenter.default.post(name: Self.snapshotRequest, object: store, userInfo: ["reply": reply])
        return answer
    }

    /// Each real change advances the version; repeats and an empty string where none is stored do
    /// not. A new instance over the same file — the next process — reads the same version.
    @Test
    func version_givenChanges_expectAdvancedPerRealChangeAndPersisted() throws {
        let dir = makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = BackgroundDeliveryContextStore(fileManager: .default, directoryURL: dir)
        #expect(snapshot(of: store)?.version == 0)

        store.setUserId("user-a")
        store.setUserId("user-a")
        store.setUserId("user-b")
        store.setUserId("user-a")
        store.setApiHost("cdp.customer.io/v1")
        store.setUserId("")
        store.setUserId(nil)

        let current = try #require(snapshot(of: store))
        #expect(current.userId == nil)
        #expect(current.version == 4)
        let relaunched = BackgroundDeliveryContextStore(fileManager: .default, directoryURL: dir)
        #expect(snapshot(of: relaunched)?.version == 4)
        #expect(snapshot(of: relaunched)?.userId == nil)
    }

    /// The change notification carries the version the change produced.
    @Test
    func changeNotification_expectTheNewVersion() {
        let dir = makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = BackgroundDeliveryContextStore(fileManager: .default, directoryURL: dir)
        let versions = Synchronized<[UInt64]>([])
        let token = NotificationCenter.default.addObserver(forName: Self.changeNotification, object: store, queue: nil) { note in
            if let version = note.userInfo?["userVersion"] as? UInt64 { versions.mutating { $0.append(version) } }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        store.setUserId("user-a")
        store.reset()

        #expect(versions.wrappedValue == [1, 2])
    }

    /// A file written before the version existed reads as version 0 and keeps its user; the file
    /// written after it still decodes as the public context an older build reads.
    @Test
    func file_givenTheFormatBeforeTheVersion_expectReadAndStillReadableByOlderBuilds() throws {
        let dir = makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("delivery_context.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(BackgroundDeliveryContext(userId: "user-a", apiHost: "cdp.customer.io/v1")).write(to: file)

        let store = BackgroundDeliveryContextStore(fileManager: .default, directoryURL: dir)
        #expect(store.currentUserId == "user-a")
        #expect(snapshot(of: store)?.version == 0)
        store.setUserId("user-b")

        let older = try JSONDecoder().decode(BackgroundDeliveryContext.self, from: Data(contentsOf: file))
        #expect(older == BackgroundDeliveryContext(userId: "user-b", apiHost: "cdp.customer.io/v1"))
        #expect(snapshot(of: BackgroundDeliveryContextStore(fileManager: .default, directoryURL: dir))?.version == 1)
    }

    /// A request is answered only by the store it names.
    @Test
    func snapshotRequest_givenAnotherStore_expectNoAnswer() {
        let dir = makeDirectory()
        let otherDir = makeDirectory()
        defer {
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.removeItem(at: otherDir)
        }
        let store = BackgroundDeliveryContextStore(fileManager: .default, directoryURL: dir)
        let other = BackgroundDeliveryContextStore(fileManager: .default, directoryURL: otherDir)
        other.setUserId("user-x")

        #expect(snapshot(of: store)?.userId == nil)
        #expect(snapshot(of: store)?.version == 0)
    }
}

/// The context record's lineage, and failing closed when an identity write fails. Names are
/// matched by their string values, as another module matches them.
@Suite("BackgroundDeliveryContextStore lineage")
struct ContextStoreLineageTests {
    private static let snapshotRequest = Notification.Name("io.customer.sdk.BackgroundDeliveryContextStore.userSnapshotRequest")
    private static let filename = "delivery_context.json"

    private struct Snapshot: Equatable {
        let userId: String?
        let version: UInt64
        let lineage: String
    }

    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func snapshot(of store: BackgroundDeliveryContextStore) -> Snapshot? {
        var answer: Snapshot?
        let reply: (String?, UInt64, String) -> Void = { answer = Snapshot(userId: $0, version: $1, lineage: $2) }
        NotificationCenter.default.post(name: Self.snapshotRequest, object: store, userInfo: ["reply": reply])
        return answer
    }

    /// A new record gets a lineage, written at once, so the next process on the same file reads
    /// the same one.
    @Test
    func lineage_givenNoFile_expectFreshLineagePersistedForTheNextProcess() throws {
        let dir = makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = try #require(snapshot(of: BackgroundDeliveryContextStore(fileManager: .default, directoryURL: dir)))
        #expect(!first.lineage.isEmpty)

        let relaunched = BackgroundDeliveryContextStore(fileManager: .default, directoryURL: dir)
        #expect(snapshot(of: relaunched) == first)
    }

    /// The record is lost — deleted, or no longer decodable. The same user identified again
    /// reaches the same version, but in a new lineage, so the pair never repeats.
    @Test(arguments: [false, true])
    func lineage_givenRecordLost_expectANewLineageAtTheSameCount(corrupted: Bool) throws {
        let dir = makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = BackgroundDeliveryContextStore(fileManager: .default, directoryURL: dir)
        store.setUserId("user-a")
        let before = try #require(snapshot(of: store))
        let file = dir.appendingPathComponent(Self.filename)
        if corrupted {
            try Data("{\"userId\": 42".utf8).write(to: file)
        } else {
            try FileManager.default.removeItem(at: file)
        }

        let replaced = BackgroundDeliveryContextStore(fileManager: .default, directoryURL: dir)
        replaced.setUserId("user-a")
        let after = try #require(snapshot(of: replaced))

        #expect(after.userId == before.userId)
        #expect(after.version == before.version)
        #expect(after.lineage != before.lineage)
    }

    /// A file from before the lineage keeps its user and version and is given a lineage, written
    /// at once and kept by the next process.
    @Test
    func lineage_givenFileFromBeforeTheLineage_expectUserAndVersionKeptAndALineagePersisted() throws {
        let dir = makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"userId":"user-a","userVersion":3}"#.utf8).write(to: dir.appendingPathComponent(Self.filename))

        let first = try #require(snapshot(of: BackgroundDeliveryContextStore(fileManager: .default, directoryURL: dir)))
        #expect(first.userId == "user-a")
        #expect(first.version == 3)
        #expect(snapshot(of: BackgroundDeliveryContextStore(fileManager: .default, directoryURL: dir)) == first)
    }

    /// A change of user that cannot be written must not leave the old user's record on disk for
    /// the next process: the stale file is removed, and the next process starts a new lineage.
    /// This process keeps the change it made.
    @Test
    func failedUserWrite_expectTheStaleRecordRemoved() throws {
        let dir = makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let failWrites = Synchronized(false)
        let store = BackgroundDeliveryContextStore(fileManager: .default, directoryURL: dir) { data, url in
            if failWrites.wrappedValue { throw CocoaError(.fileWriteNoPermission) }
            try data.write(to: url, options: .atomic)
        }
        store.setUserId("user-a")
        let before = try #require(snapshot(of: store))

        failWrites.wrappedValue = true
        store.setUserId("user-b")

        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent(Self.filename).path))
        #expect(snapshot(of: store)?.userId == "user-b")
        #expect(snapshot(of: store)?.version == 2)
        let next = try #require(snapshot(of: BackgroundDeliveryContextStore(fileManager: .default, directoryURL: dir)))
        #expect(next.userId == nil)
        #expect(next.lineage != before.lineage)
    }

    /// Control: a failed write that changes no user leaves the record on disk as it was.
    @Test
    func failedWriteOfAnotherField_expectTheRecordKept() throws {
        let dir = makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let failWrites = Synchronized(false)
        let store = BackgroundDeliveryContextStore(fileManager: .default, directoryURL: dir) { data, url in
            if failWrites.wrappedValue { throw CocoaError(.fileWriteNoPermission) }
            try data.write(to: url, options: .atomic)
        }
        store.setUserId("user-a")

        failWrites.wrappedValue = true
        store.setApiHost("cdp.customer.io/v1")

        #expect(BackgroundDeliveryContextStore(fileManager: .default, directoryURL: dir).currentUserId == "user-a")
    }

    /// Storage unavailable for both the write and the removal: nothing can be persisted. This
    /// process still holds the change, so it refuses what the change ended.
    @Test
    func failedUserWriteAndRemoval_expectThisProcessStillHoldsTheChange() throws {
        let dir = makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let failWrites = Synchronized(false)
        let fileManager = UnremovableFileManager()
        let store = BackgroundDeliveryContextStore(fileManager: fileManager, directoryURL: dir) { data, url in
            if failWrites.wrappedValue { throw CocoaError(.fileWriteNoPermission) }
            try data.write(to: url, options: .atomic)
        }
        store.setUserId("user-a")

        failWrites.wrappedValue = true
        store.setUserId("user-b")

        #expect(snapshot(of: store)?.userId == "user-b")
        #expect(snapshot(of: store)?.version == 2)
    }
}

/// Refuses every removal, as storage that cannot be written does.
private final class UnremovableFileManager: FileManager {
    override func removeItem(at URL: URL) throws {
        throw CocoaError(.fileWriteNoPermission)
    }
}

/// Records each change the store announces, as it is posted.
private final class UserChangeRecorder: @unchecked Sendable {
    private let recorded = Synchronized<[String?]>([])
    private var token: NSObjectProtocol?

    var changes: [String?] { recorded.wrappedValue }

    init(observing store: BackgroundDeliveryContextStore) {
        self.token = NotificationCenter.default.addObserver(
            forName: BackgroundDeliveryContextStore.userIdDidChangeNotification, object: store, queue: nil
        ) { [recorded] notification in
            let userId = notification.userInfo?[BackgroundDeliveryContextStore.userIdKey] as? String
            recorded.mutating { $0.append(userId) }
        }
    }

    deinit {
        if let token { NotificationCenter.default.removeObserver(token) }
    }
}

private final class StubCdpApiKeyProvider: BackgroundDeliveryCdpApiKeyProvider {
    let value: String?
    init(value: String?) {
        self.value = value
    }

    var cdpApiKey: String? { value }
}
