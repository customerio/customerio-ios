@testable import CioInternalCommon
@testable import CioLocation
import Foundation
import SharedTests
import Testing

@Suite("FileLastLocationStateStore")
struct FileLastLocationStateStoreTests {
    private func makeTempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func makeStore(directory: URL) -> FileLastLocationStateStore {
        FileLastLocationStateStore(fileManager: .default, directoryURL: directory)
    }

    @Test
    func load_whenFileDoesNotExist_returnsNil() {
        let dir = makeTempDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = makeStore(directory: dir)
        #expect(store.load() == nil)
    }

    @Test
    func save_andLoad_roundTripsState() {
        let dir = makeTempDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = makeStore(directory: dir)
        let location = LocationData(latitude: 37.7749, longitude: -122.4194)
        let timestamp = Date(timeIntervalSince1970: 1700000000)
        var state = LastLocationState()
        state.cachedLocation = location
        state.lastSynced = LastSyncedRecord(location: location, timestamp: timestamp)
        store.save(state)
        let loaded = store.load()
        #expect(loaded != nil)
        #expect(loaded?.cachedLocation?.latitude == 37.7749)
        #expect(loaded?.cachedLocation?.longitude == -122.4194)
        #expect(loaded?.lastSynced?.location.latitude == 37.7749)
        #expect(loaded?.lastSynced?.timestamp == timestamp)
    }

    @Test
    func save_emptyState_andLoad_returnsEmptyState() {
        let dir = makeTempDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = makeStore(directory: dir)
        store.save(LastLocationState())
        let loaded = store.load()
        #expect(loaded != nil)
        #expect(loaded?.cachedLocation == nil)
        #expect(loaded?.lastSynced == nil)
    }

    @Test
    func save_twice_secondSaveOverwrites() {
        let dir = makeTempDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = makeStore(directory: dir)
        var state1 = LastLocationState()
        state1.cachedLocation = LocationData(latitude: 1, longitude: 2)
        store.save(state1)
        var state2 = LastLocationState()
        state2.cachedLocation = LocationData(latitude: 3, longitude: 4)
        store.save(state2)
        let loaded = store.load()
        #expect(loaded?.cachedLocation?.latitude == 3)
        #expect(loaded?.cachedLocation?.longitude == 4)
    }

    @Test
    func clear_deletesFile_thenLoadReturnsNil() {
        let dir = makeTempDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = makeStore(directory: dir)
        var state = LastLocationState()
        state.cachedLocation = LocationData(latitude: 1, longitude: 2)
        store.save(state)
        #expect(store.load() != nil)
        store.clear()
        #expect(store.load() == nil)
    }

    @Test
    func concurrentLoadSaveClear_doesNotCrash_andFinalLoadIsConsistent() async {
        let dir = makeTempDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = makeStore(directory: dir)
        await withTaskGroup(of: Void.self) { group in
            for i in 0 ..< 20 {
                group.addTask {
                    for j in 0 ..< 10 {
                        switch (i + j) % 3 {
                        case 0:
                            var state = LastLocationState()
                            state.cachedLocation = LocationData(latitude: Double(i), longitude: Double(j))
                            store.save(state)
                        case 1:
                            _ = store.load()
                        case 2:
                            store.clear()
                        default:
                            break
                        }
                    }
                }
            }
        }
        _ = store.load()
    }
}
