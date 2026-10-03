@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioLocationGeofence
import Foundation
import SharedTests
import Testing

/// Resolves no Application Support directory: the only way to reach the no-location branch.
private final class NoApplicationSupportFileManager: FileManager {
    override func urls(for directory: FileManager.SearchPathDirectory, in domainMask: FileManager.SearchPathDomainMask) -> [URL] {
        []
    }
}

@Suite("PendingGeofenceMetricStore")
struct PendingGeofenceMetricStoreTests {
    private func makeTempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func makeStore(directory: URL, logger: Logger = LoggerMock()) -> PendingGeofenceMetricStore {
        PendingGeofenceMetricStore(logger: logger, fileManager: .default, directoryURL: directory)
    }

    private func makeMetric(
        geofenceId: String = "geo_1",
        transition: GeofenceTransition = .enter,
        transitionId: String = "txn_store"
    ) -> PendingGeofenceMetric {
        PendingGeofenceMetric(
            geofenceId: geofenceId,
            transition: transition,
            timestamp: Date(timeIntervalSince1970: 1700000000),
            userId: "user_store",
            name: nil,
            transitionId: transitionId
        )
    }

    // MARK: - Basic append + loadAll

    @Test
    func loadAll_givenEmpty_expectEmptyArray() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = makeStore(directory: dir)

        let items = await store.rows()

        #expect(items.isEmpty)
    }

    @Test
    func append_givenMetric_expectPersisted() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = makeStore(directory: dir)
        let metric = makeMetric()

        let appended = await store.append([metric])
        let items = await store.rows()

        #expect(appended == .persisted)
        #expect(items.count == 1)
        #expect(items.first == metric)
    }

    @Test
    func appendLoad_givenMetadata_expectRoundTripPreserved() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = makeStore(directory: dir)
        let metric = PendingGeofenceMetric(
            geofenceId: "geo_1", transition: .enter,
            timestamp: Date(timeIntervalSince1970: 1700000000),
            userId: "user_42", name: "HQ", transitionId: "txn_1",
            metadata: ["category": .string("office"), "priority": .int(3)]
        )

        _ = await store.append([metric])

        #expect(await store.rows().first?.metadata == ["category": .string("office"), "priority": .int(3)])
    }

    @Test
    func decode_givenLegacyRowWithoutMetadata_expectNilMetadata() throws {
        let legacy = """
        {"geofence_id":"geo_1","transition":"enter","timestamp":1,"user_id":"user_1","transition_id":"txn_1"}
        """
        let metric = try JSONDecoder().decode(PendingGeofenceMetric.self, from: Data(legacy.utf8))
        #expect(metric.metadata == nil)
        #expect(metric.geofenceId == "geo_1")
    }

    @Test
    func append_givenMultiple_expectAllPersistedInOrder() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = makeStore(directory: dir)
        let first = makeMetric(geofenceId: "geo_1")
        let second = makeMetric(geofenceId: "geo_2")

        _ = await store.append([first])
        _ = await store.append([second])
        let items = await store.rows()

        #expect(items.count == 2)
        #expect(items[0] == first)
        #expect(items[1] == second)
    }

    // MARK: - Capacity bound

    @Test
    func append_givenOverCapacity_expectOldestDropped() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = makeStore(directory: dir)

        // Cap is 100, so the first 5 drop.
        for i in 0 ..< 105 {
            _ = await store.append([makeMetric(geofenceId: "geo_\(i)")])
        }
        let items = await store.rows()

        #expect(items.count == 100)
        #expect(items.first?.geofenceId == "geo_5")
        #expect(items.last?.geofenceId == "geo_104")
    }

    @Test
    func append_givenExactlyAtCapacity_expectAllPreserved() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = makeStore(directory: dir)

        // Exactly the cap; guards an off-by-one in the `>` check.
        for i in 0 ..< 100 {
            _ = await store.append([makeMetric(geofenceId: "geo_\(i)")])
        }
        let items = await store.rows()

        #expect(items.count == 100)
        #expect(items.first?.geofenceId == "geo_0")
        #expect(items.last?.geofenceId == "geo_99")
    }

    @Test
    func append_givenBatchOverCapacity_expectOldestDropped() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = makeStore(directory: dir)

        let batch = (0 ..< 105).map { makeMetric(geofenceId: "geo_\($0)") }
        _ = await store.append(batch)
        let items = await store.rows()

        #expect(items.count == 100)
        #expect(items.first?.geofenceId == "geo_5")
        #expect(items.last?.geofenceId == "geo_104")
    }

    // MARK: - Remove

    @Test
    func remove_givenExistingKey_expectRemovedAndReturnTrue() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = makeStore(directory: dir)
        let toKeep = makeMetric(geofenceId: "keep")
        let toRemove = makeMetric(geofenceId: "remove")
        _ = await store.append([toKeep])
        _ = await store.append([toRemove])

        let removed = await store.remove(key: toRemove.key)
        let items = await store.rows()

        #expect(removed == true)
        #expect(items.count == 1)
        #expect(items.first == toKeep)
    }

    @Test
    func remove_givenMissingKey_expectReturnFalseAndNoChange() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = makeStore(directory: dir)
        let metric = makeMetric()
        _ = await store.append([metric])

        let removed = await store.remove(key: "nonexistent_key")
        let items = await store.rows()

        #expect(removed == false)
        #expect(items.count == 1)
    }

    // MARK: - Append dedup + atomic fan-out

    @Test
    func append_givenDuplicateKeysInBatchAndOnDisk_expectDeduped() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = makeStore(directory: dir)
        let existing = makeMetric(geofenceId: "geo_1") // key already on disk
        _ = await store.append([existing])

        // Repeats the on-disk key plus an in-batch duplicate.
        let batch = [existing, makeMetric(geofenceId: "geo_2"), makeMetric(geofenceId: "geo_2")]
        let appended = await store.append(batch)
        let items = await store.rows()

        #expect(appended == .persisted)
        #expect(items.count == 2)
        #expect(Set(items.map(\.geofenceId)) == ["geo_1", "geo_2"])
    }

    @Test
    func append_givenSameTransitionDifferentGeosets_expectBothRowsKeptInOneWrite() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = makeStore(directory: dir)
        let timestamp = Date(timeIntervalSince1970: 1700000000)
        // One transition fanned out to two geosets: same key fields, distinct `geosetId`.
        let rowY = PendingGeofenceMetric(
            geofenceId: "geo_1", transition: .enter, timestamp: timestamp,
            userId: "user_1", name: nil, transitionId: "txn", geosetId: "set_y"
        )
        let rowZ = PendingGeofenceMetric(
            geofenceId: "geo_1", transition: .enter, timestamp: timestamp,
            userId: "user_1", name: nil, transitionId: "txn", geosetId: "set_z"
        )

        let appended = await store.append([rowY, rowZ])
        let items = await store.rows()

        #expect(appended == .persisted)
        #expect(rowY.key != rowZ.key) // geoset suffix keeps fan-out rows distinct
        #expect(items.count == 2)
        #expect(Set(items.compactMap(\.geosetId)) == ["set_y", "set_z"])
    }

    /// Two visits' DWELLs on one fence in the same second are two facts. Keyed without their
    /// occurrence, the second was dropped as a duplicate while the append still reported it
    /// persisted, and removing either row's key removed both.
    @Test
    func append_givenDistinctOccurrencesInTheSameSecond_expectBothKeptAndRemovedSeparately() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = makeStore(directory: dir)
        let first = makeMetric(transition: .dwell, transitionId: "visit-a")
        let second = makeMetric(transition: .dwell, transitionId: "visit-b")

        #expect(await store.append([first]) == .persisted)
        #expect(await store.append([second]) == .persisted)

        #expect(await store.rows() == [first, second])
        #expect(await store.remove(key: first.key))
        #expect(await store.rows() == [second])
    }

    /// A retried fact repeats its occurrence: it lands on the row already queued, which keeps its
    /// original timestamp and evidence.
    @Test
    func append_givenTheSameOccurrenceRetried_expectTheFirstRowKept() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = makeStore(directory: dir)
        let original = PendingGeofenceMetric(
            geofenceId: "geo_1", transition: .dwell, timestamp: Date(timeIntervalSince1970: 1700000000.2),
            userId: "user_1", name: nil, transitionId: "visit-a", geosetId: "set_y",
            visitId: "visit-a", dwellThresholdSeconds: 60, dwellDurationSeconds: 61, detectionSource: "location_evidence"
        )
        let retried = PendingGeofenceMetric(
            geofenceId: "geo_1", transition: .dwell, timestamp: Date(timeIntervalSince1970: 1700000000.7),
            userId: "user_1", name: nil, transitionId: "visit-a", geosetId: "set_y",
            visitId: "visit-a", dwellThresholdSeconds: 60, dwellDurationSeconds: 62, detectionSource: "location_evidence"
        )

        _ = await store.append([original])
        #expect(await store.append([retried]) == .persisted)

        #expect(await store.rows() == [original])
    }

    @Test
    func append_givenEmpty_expectNoOpReturnTrue() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = makeStore(directory: dir)
        _ = await store.append([makeMetric()])

        let appended = await store.append([])
        let items = await store.rows()

        #expect(appended == .persisted)
        #expect(items.count == 1)
    }

    @Test
    func decode_givenLegacyRowWithoutGeosetId_expectNilGeosetId() throws {
        let legacyJson = """
        {"geofence_id":"geo_1","transition":"enter","timestamp":1700000000,"user_id":"user_1","transition_id":"txn_legacy"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let metric = try decoder.decode(PendingGeofenceMetric.self, from: Data(legacyJson.utf8))

        #expect(metric.geosetId == nil)
        #expect(metric.key == "geo%5F1_enter_1700000000_user%5F1_txn%5Flegacy")
    }

    /// Unescaped, `a_42` with no geoset and `a` in geoset `42` would both key `..._a_42`.
    @Test
    func key_givenAComponentHoldingTheSeparator_expectNoCollisionAcrossTheBoundary() {
        let timestamp = Date(timeIntervalSince1970: 1700000000)
        let underscoreInUserId = PendingGeofenceMetric(
            geofenceId: "geo", transition: .enter, timestamp: timestamp,
            userId: "a_42", name: nil, transitionId: "txn"
        )
        let userInGeoset = PendingGeofenceMetric(
            geofenceId: "geo", transition: .enter, timestamp: timestamp,
            userId: "a", name: nil, transitionId: "txn", geosetId: "42"
        )

        #expect(underscoreInUserId.key != userInGeoset.key)
    }

    // MARK: - Persistence across instances

    @Test
    func loadAll_givenNewStoreInstance_expectLoadsFromDisk() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let metric = makeMetric()

        let firstStore = makeStore(directory: dir)
        _ = await firstStore.append([metric])

        let secondStore = makeStore(directory: dir)
        let items = await secondStore.rows()

        #expect(items == [metric])
    }

    // MARK: - Concurrent safety

    @Test
    func concurrentOperations_expectCapacityInvariantHolds() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = makeStore(directory: dir)

        await withTaskGroup(of: Void.self) { group in
            for i in 0 ..< 20 {
                group.addTask {
                    for j in 0 ..< 10 {
                        switch (i + j) % 3 {
                        case 0:
                            _ = await store.append([PendingGeofenceMetric(
                                geofenceId: "geo_\(i)_\(j)",
                                transition: .enter,
                                timestamp: Date(),
                                userId: "user_1",
                                name: nil,
                                transitionId: "txn_\(i)_\(j)"
                            )])
                        case 1:
                            _ = await store.rows()
                        case 2:
                            _ = await store.remove(key: "geo_\(i)_\(j)_enter_0")
                        default:
                            break
                        }
                    }
                }
            }
        }

        let items = await store.rows()
        #expect(items.count <= 100)
    }

    // MARK: - Resilience to bad rows and unreadable files

    private func queueFile(in directory: URL) -> URL {
        directory.appendingPathComponent("pending_geofence_metrics.json")
    }

    private func plant(_ json: String, in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: queueFile(in: directory))
    }

    /// A row missing `user_id` (non-optional here, nullable on Android).
    private static let oneGoodOneBadRow = """
    [
      {"geofence_id":"geo_1","transition":"enter","timestamp":1700000000,"user_id":"user_store","transition_id":"txn_store"},
      {"geofence_id":"geo_2","transition":"enter","timestamp":1700000001,"transition_id":"txn_broken"}
    ]
    """

    @Test
    func read_givenNoResolvableFileLocation_expectUnreadableAndLogged() async {
        let logger = LoggerMock()
        let store = PendingGeofenceMetricStore(
            logger: logger,
            fileManager: NoApplicationSupportFileManager(),
            directoryURL: nil
        )

        #expect(await store.read() == .unreadable)
        #expect(logger.errorReceivedInvocations.contains { $0.message.contains("the file location could not be resolved") })
    }

    @Test
    func read_givenOneUndecodableRow_expectTheOtherRowSurvives() async throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try plant(Self.oneGoodOneBadRow, in: dir)
        let store = makeStore(directory: dir)

        let result = await store.read()

        #expect(result == .rows([makeMetric()]))
    }

    @Test
    func read_givenOneUndecodableRow_expectTheDropCounted() async throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try plant(Self.oneGoodOneBadRow, in: dir)
        let logger = LoggerMock()
        let store = makeStore(directory: dir, logger: logger)

        _ = await store.read()

        #expect(logger.errorReceivedInvocations.contains { $0.message.contains("skipped 1 of 2 row(s)") })
    }

    @Test
    func append_givenOneUndecodableRow_expectTheGoodRowKept() async throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try plant(Self.oneGoodOneBadRow, in: dir)
        let store = makeStore(directory: dir)

        #expect(await store.append([makeMetric(geofenceId: "geo_3", transitionId: "txn_3")]) == .persisted)

        #expect(await store.rows().map(\.geofenceId) == ["geo_1", "geo_3"])
    }

    /// A file the process can't read in a directory it can still write, so an atomic write would
    /// otherwise succeed.
    @Test
    func append_givenAnUnreadableFile_expectRefusedAndTheQueueUntouched() async throws {
        let dir = makeTempDirectory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: queueFile(in: dir).path)
            try? FileManager.default.removeItem(at: dir)
        }
        let store = makeStore(directory: dir)
        #expect(await store.append([makeMetric()]) == .persisted)
        let before = try Data(contentsOf: queueFile(in: dir))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: queueFile(in: dir).path)

        let appended = await store.append([makeMetric(geofenceId: "geo_new", transitionId: "txn_new")])

        #expect(appended == .refusedUnreadable)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: queueFile(in: dir).path)
        #expect(try Data(contentsOf: queueFile(in: dir)) == before)
    }

    @Test
    func read_givenAnUnreadableFile_expectUnreadableNotEmpty() async throws {
        let dir = makeTempDirectory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: queueFile(in: dir).path)
            try? FileManager.default.removeItem(at: dir)
        }
        let logger = LoggerMock()
        let store = makeStore(directory: dir, logger: logger)
        _ = await store.append([makeMetric()])
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: queueFile(in: dir).path)

        #expect(await store.read() == .unreadable)
        #expect(logger.errorReceivedInvocations.contains { $0.message.contains("unreadable: the file could not be read") })
    }

    @Test
    func remove_givenAnUnreadableFile_expectRefused() async throws {
        let dir = makeTempDirectory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: queueFile(in: dir).path)
            try? FileManager.default.removeItem(at: dir)
        }
        let store = makeStore(directory: dir)
        let metric = makeMetric()
        _ = await store.append([metric])
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: queueFile(in: dir).path)

        #expect(await store.remove(key: metric.key) == false)
    }

    @Test
    func append_givenAFileThatIsNotARowArray_expectTheWriteProceeds() async throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try plant("{\"not\":\"an array\"}", in: dir)
        let logger = LoggerMock()
        let store = makeStore(directory: dir, logger: logger)

        #expect(await store.append([makeMetric()]) == .persisted)

        #expect(await store.rows() == [makeMetric()])
        #expect(logger.errorReceivedInvocations.contains { $0.message.contains("unreadable: the file is not a row array") })
    }
}
