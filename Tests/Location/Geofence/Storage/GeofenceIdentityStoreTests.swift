@testable import CioInternalCommon
@testable import CioLocation
import Foundation
import SharedTests
import Testing

@Suite("GeofenceIdentityStore")
struct GeofenceIdentityStoreTests {
    @Test
    func currentUserId_givenNeverWritten_expectNil() {
        let store = GeofenceIdentityStore(storage: InMemorySharedKeyValueStorage())
        #expect(store.currentUserId == nil)
    }

    @Test
    func setUserId_givenValue_expectPersistedAndReadable() {
        let store = GeofenceIdentityStore(storage: InMemorySharedKeyValueStorage())
        store.setUserId("user_42")
        #expect(store.currentUserId == "user_42")
    }

    @Test
    func setUserId_givenEmptyString_expectTreatedAsClear() {
        let store = GeofenceIdentityStore(storage: InMemorySharedKeyValueStorage())
        store.setUserId("user_42")
        store.setUserId("")
        #expect(store.currentUserId == nil)
    }

    @Test
    func setUserId_givenSecondCall_expectOverwritten() {
        let store = GeofenceIdentityStore(storage: InMemorySharedKeyValueStorage())
        store.setUserId("user_42")
        store.setUserId("user_43")
        #expect(store.currentUserId == "user_43")
    }

    @Test
    func clearUserId_givenValue_expectNilAfter() {
        let store = GeofenceIdentityStore(storage: InMemorySharedKeyValueStorage())
        store.setUserId("user_42")
        store.clearUserId()
        #expect(store.currentUserId == nil)
    }

    @Test
    func currentUserId_givenNewStoreOnSameStorage_expectLoadsPreviousValue() {
        let storage = InMemorySharedKeyValueStorage()
        GeofenceIdentityStore(storage: storage).setUserId("user_42")
        let reborn = GeofenceIdentityStore(storage: storage)
        #expect(reborn.currentUserId == "user_42")
    }
}
