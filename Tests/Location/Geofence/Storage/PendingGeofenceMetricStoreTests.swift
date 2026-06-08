@testable import CioInternalCommon
@testable import CioLocation
import Foundation
import SharedTests
import Testing

@Suite("PendingGeofenceMetricStore")
struct PendingGeofenceMetricStoreTests {
    private func makeTempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func makeStore(directory: URL) -> PendingGeofenceMetricStore {
        PendingGeofenceMetricStore(fileManager: .default, directoryURL: directory)
    }

    private func makeMetric(geofenceId: String = "geo_1", transition: GeofenceTransition = .enter) -> PendingGeofenceMetric {
        PendingGeofenceMetric(
            geofenceId: geofenceId,
            transition: transition,
            latitude: 12.34,
            longitude: 56.78,
            timestamp: Date(timeIntervalSince1970: 1700000000)
        )
    }

    // MARK: - Basic append + loadAll

    @Test
    func loadAll_givenEmpty_expectEmptyArray() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = makeStore(directory: dir)

        let items = await store.loadAll()

        #expect(items.isEmpty)
    }

    @Test
    func append_givenMetric_expectPersisted() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = makeStore(directory: dir)
        let metric = makeMetric()

        let appended = await store.append(metric)
        let items = await store.loadAll()

        #expect(appended == true)
        #expect(items.count == 1)
        #expect(items.first == metric)
    }

    @Test
    func append_givenMultiple_expectAllPersistedInOrder() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = makeStore(directory: dir)
        let first = makeMetric(geofenceId: "geo_1")
        let second = makeMetric(geofenceId: "geo_2")

        _ = await store.append(first)
        _ = await store.append(second)
        let items = await store.loadAll()

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
            _ = await store.append(makeMetric(geofenceId: "geo_\(i)"))
        }
        let items = await store.loadAll()

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
            _ = await store.append(makeMetric(geofenceId: "geo_\(i)"))
        }
        let items = await store.loadAll()

        #expect(items.count == 100)
        #expect(items.first?.geofenceId == "geo_0")
        #expect(items.last?.geofenceId == "geo_99")
    }

    // MARK: - Remove

    @Test
    func remove_givenExistingKey_expectRemovedAndReturnTrue() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = makeStore(directory: dir)
        let toKeep = makeMetric(geofenceId: "keep")
        let toRemove = makeMetric(geofenceId: "remove")
        _ = await store.append(toKeep)
        _ = await store.append(toRemove)

        let removed = await store.remove(key: toRemove.key)
        let items = await store.loadAll()

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
        _ = await store.append(metric)

        let removed = await store.remove(key: "nonexistent_key")
        let items = await store.loadAll()

        #expect(removed == false)
        #expect(items.count == 1)
    }

    // MARK: - RemoveAll

    @Test
    func removeAll_givenAllPresent_expectAllRemoved() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = makeStore(directory: dir)
        let first = makeMetric(geofenceId: "geo_1")
        let second = makeMetric(geofenceId: "geo_2")
        _ = await store.append(first)
        _ = await store.append(second)

        let success = await store.removeAll(keys: [first.key, second.key])
        let items = await store.loadAll()

        #expect(success == true)
        #expect(items.isEmpty)
    }

    @Test
    func removeAll_givenPartialMatch_expectOnlyMatchingRemoved() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = makeStore(directory: dir)
        let toKeep = makeMetric(geofenceId: "keep")
        let toRemove = makeMetric(geofenceId: "remove")
        _ = await store.append(toKeep)
        _ = await store.append(toRemove)

        let success = await store.removeAll(keys: [toRemove.key, "nonexistent_key"])
        let items = await store.loadAll()

        #expect(success == true)
        #expect(items == [toKeep])
    }

    @Test
    func removeAll_givenEmptySet_expectNoOp() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = makeStore(directory: dir)
        _ = await store.append(makeMetric())

        let success = await store.removeAll(keys: [])
        let items = await store.loadAll()

        #expect(success == true)
        #expect(items.count == 1)
    }

    // MARK: - Duplicate-key dedup at append

    @Test
    func append_givenDuplicateKey_expectNoOpReturnTrue() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = makeStore(directory: dir)
        let metric = makeMetric()
        _ = await store.append(metric)

        // Same geofenceId + transition + timestamp produces the same composite key.
        // Storage layer rejects the duplicate so a cooldown-slip can't produce two rows.
        let duplicate = makeMetric()
        let appended = await store.append(duplicate)
        let items = await store.loadAll()

        #expect(appended == true)
        #expect(items.count == 1)
    }

    // MARK: - Clear

    @Test
    func clearAll_givenItems_expectEmpty() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = makeStore(directory: dir)
        _ = await store.append(makeMetric(geofenceId: "geo_1"))
        _ = await store.append(makeMetric(geofenceId: "geo_2"))

        await store.clearAll()
        let items = await store.loadAll()

        #expect(items.isEmpty)
    }

    // MARK: - Persistence across instances

    @Test
    func loadAll_givenNewStoreInstance_expectLoadsFromDisk() async {
        let dir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let metric = makeMetric()

        let firstStore = makeStore(directory: dir)
        _ = await firstStore.append(metric)

        let secondStore = makeStore(directory: dir)
        let items = await secondStore.loadAll()

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
                            _ = await store.append(PendingGeofenceMetric(
                                geofenceId: "geo_\(i)_\(j)",
                                transition: .enter,
                                latitude: nil,
                                longitude: nil,
                                timestamp: Date()
                            ))
                        case 1:
                            _ = await store.loadAll()
                        case 2:
                            await store.clearAll()
                        default:
                            break
                        }
                    }
                }
            }
        }

        let items = await store.loadAll()
        #expect(items.count <= 100)
    }
}
