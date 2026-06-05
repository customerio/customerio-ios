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
}
