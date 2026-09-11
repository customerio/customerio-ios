@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioLocationGeofence
import Foundation
import SharedTests
import Testing

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

        #expect(appended == true)
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
        // A row persisted before metadata existed must still decode (missing key → nil).
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

        // Append 105 metrics; cap is 100. First 5 should be dropped.
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

        // Append exactly 100 (the cap); guards against an off-by-one in the `>` check.
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

        // A single batch larger than the cap must trim to the newest 100 in that one write.
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

        // Batch repeats the on-disk key and an in-batch duplicate; both must be skipped so a
        // cooldown-slip or re-fan-out can't produce duplicate rows.
        let batch = [existing, makeMetric(geofenceId: "geo_2"), makeMetric(geofenceId: "geo_2")]
        let appended = await store.append(batch)
        let items = await store.rows()

        #expect(appended == true)
        #expect(items.count == 2)
        #expect(Set(items.map(\.geofenceId)) == ["geo_1", "geo_2"])
    }

    @Test
    func append_givenSameTransitionDifferentGeosets_expectBothRowsKeptInOneWrite() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = makeStore(directory: dir)
        let timestamp = Date(timeIntervalSince1970: 1700000000)
        // One physical transition fanned out to two geosets: identical
        // (geofenceId, transition, timestamp), distinct geosetId suffixes. Persisted atomically.
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

        #expect(appended == true)
        #expect(rowY.key != rowZ.key) // geoset suffix keeps fan-out rows distinct
        #expect(items.count == 2)
        #expect(Set(items.compactMap(\.geosetId)) == ["set_y", "set_z"])
    }

    @Test
    func append_givenEmpty_expectNoOpReturnTrue() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = makeStore(directory: dir)
        _ = await store.append([makeMetric()])

        let appended = await store.append([])
        let items = await store.rows()

        #expect(appended == true)
        #expect(items.count == 1)
    }

    @Test
    func decode_givenLegacyRowWithoutGeosetId_expectNilGeosetId() throws {
        // Rows persisted by pre-geoset SDK versions have no `geoset_id` field and
        // must keep decoding after an upgrade.
        let legacyJson = """
        {"geofence_id":"geo_1","transition":"enter","timestamp":1700000000,"user_id":"user_1","transition_id":"txn_legacy"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let metric = try decoder.decode(PendingGeofenceMetric.self, from: Data(legacyJson.utf8))

        #expect(metric.geosetId == nil)
        #expect(metric.key == "geo_1_enter_1700000000")
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

    /// The queue file path, so a test can plant bytes the encoder would never produce.
    private func queueFile(in directory: URL) -> URL {
        directory.appendingPathComponent("pending_geofence_metrics.json")
    }

    private func plant(_ json: String, in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: queueFile(in: directory))
    }

    /// A row missing `user_id` — the schema-evolution case, since `userId` is non-optional here
    /// while Android's is nullable. One of these used to discard every other row with it.
    private static let oneGoodOneBadRow = """
    [
      {"geofence_id":"geo_1","transition":"enter","timestamp":1700000000,"user_id":"user_store","transition_id":"txn_store"},
      {"geofence_id":"geo_2","transition":"enter","timestamp":1700000001,"transition_id":"txn_broken"}
    ]
    """

    @Test
    func read_givenOneUndecodableRow_expectTheOtherRowSurvives() async throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try plant(Self.oneGoodOneBadRow, in: dir)
        let store = makeStore(directory: dir)

        let result = await store.read()

        #expect(result == .rows([makeMetric()], droppedRows: 1))
    }

    @Test
    func read_givenOneUndecodableRow_expectTheDropCounted() async throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try plant(Self.oneGoodOneBadRow, in: dir)
        let logger = LoggerMock()
        let store = makeStore(directory: dir, logger: logger)

        _ = await store.read()

        // The count is the record: a backlog that shrank and one that was thrown away are the
        // same observation without it.
        #expect(logger.errorReceivedInvocations.contains { $0.message.contains("skipped 1 of 2 row(s)") })
    }

    @Test
    func append_givenOneUndecodableRow_expectTheGoodRowKept() async throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try plant(Self.oneGoodOneBadRow, in: dir)
        let store = makeStore(directory: dir)

        #expect(await store.append([makeMetric(geofenceId: "geo_3", transitionId: "txn_3")]))

        #expect(await store.rows().map(\.geofenceId) == ["geo_1", "geo_3"])
    }

    /// The defect this ticket exists for. The file carries
    /// `completeUntilFirstUserAuthentication`, so a geofence wake before the first unlock after a
    /// reboot cannot read it — and an append that treats that as an empty queue overwrites rows
    /// that were never lost. Modelled with a file the process may not read but whose directory it
    /// may still write, which is the same shape: an atomic write would otherwise succeed.
    @Test
    func append_givenAnUnreadableFile_expectRefusedAndTheQueueUntouched() async throws {
        let dir = makeTempDirectory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: queueFile(in: dir).path)
            try? FileManager.default.removeItem(at: dir)
        }
        let store = makeStore(directory: dir)
        #expect(await store.append([makeMetric()]))
        let before = try Data(contentsOf: queueFile(in: dir))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: queueFile(in: dir).path)

        let appended = await store.append([makeMetric(geofenceId: "geo_new", transitionId: "txn_new")])

        #expect(appended == false)
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

    /// Read succeeded and the bytes are not a row array, so unlike a read failure there is nothing
    /// left to preserve — the queue reads empty and the next write reclaims the file.
    @Test
    func append_givenAFileThatIsNotARowArray_expectTheWriteProceeds() async throws {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try plant("{\"not\":\"an array\"}", in: dir)
        let logger = LoggerMock()
        let store = makeStore(directory: dir, logger: logger)

        #expect(await store.append([makeMetric()]))

        #expect(await store.rows() == [makeMetric()])
        #expect(logger.errorReceivedInvocations.contains { $0.message.contains("unreadable: the file is not a row array") })
    }
}
