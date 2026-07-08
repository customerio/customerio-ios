import CioInternalCommon
import Foundation
import Testing

@testable import CioLiveActivities

// MARK: - Helpers

private func makeStore() -> (KeyValueLiveActivityTokenStore, InMemoryKeyValueStorage) {
    let kv = InMemoryKeyValueStorage()
    return (KeyValueLiveActivityTokenStore(storage: kv), kv)
}

// MARK: - registrationSignature

struct LiveActivityRegistrationGetTests {
    @Test func getSignature_returnsNil_whenNoRecordExists() {
        let (store, _) = makeStore()
        #expect(store.registrationSignature(activityType: "OrderActivity") == nil)
    }

    @Test func getSignature_returnsNil_forUnknownActivityType() {
        let (store, _) = makeStore()
        store.setRegistrationSignature(activityType: "OrderActivity", signature: "aabbcc|user-1")
        #expect(store.registrationSignature(activityType: "ShipmentActivity") == nil)
    }

    @Test func getSignature_returnsStoredSignature() {
        let (store, _) = makeStore()
        store.setRegistrationSignature(activityType: "OrderActivity", signature: "deadbeef|user-1")
        #expect(store.registrationSignature(activityType: "OrderActivity") == "deadbeef|user-1")
    }
}

// MARK: - setRegistrationSignature

struct LiveActivityRegistrationSetTests {
    @Test func setSignature_persistsValue() {
        let (store, _) = makeStore()
        store.setRegistrationSignature(activityType: "OrderActivity", signature: "cafebabe|user-1")
        #expect(store.registrationSignature(activityType: "OrderActivity") == "cafebabe|user-1")
    }

    @Test func setSignature_upserts_onConflict() {
        let (store, _) = makeStore()
        store.setRegistrationSignature(activityType: "OrderActivity", signature: "first|user-1")
        store.setRegistrationSignature(activityType: "OrderActivity", signature: "second|user-2")
        #expect(store.registrationSignature(activityType: "OrderActivity") == "second|user-2")
    }

    @Test func setSignature_storesIndependentlyPerActivityType() {
        let (store, _) = makeStore()
        store.setRegistrationSignature(activityType: "OrderActivity", signature: "order|user-1")
        store.setRegistrationSignature(activityType: "ShipmentActivity", signature: "ship|user-1")
        #expect(store.registrationSignature(activityType: "OrderActivity") == "order|user-1")
        #expect(store.registrationSignature(activityType: "ShipmentActivity") == "ship|user-1")
    }

    @Test func setSignature_survivesReload_fromSameBackingStore() {
        let kv = InMemoryKeyValueStorage()
        KeyValueLiveActivityTokenStore(storage: kv)
            .setRegistrationSignature(activityType: "OrderActivity", signature: "persisted|user-1")
        // A fresh store instance over the same backing storage sees the value.
        let reopened = KeyValueLiveActivityTokenStore(storage: kv)
        #expect(reopened.registrationSignature(activityType: "OrderActivity") == "persisted|user-1")
    }
}

// MARK: - clearAll

struct LiveActivityRegistrationClearTests {
    @Test func clear_removesAllRecords() {
        let (store, _) = makeStore()
        store.setRegistrationSignature(activityType: "OrderActivity", signature: "aaa|u")
        store.setRegistrationSignature(activityType: "ShipmentActivity", signature: "bbb|u")
        store.clearAll()
        #expect(store.registrationSignature(activityType: "OrderActivity") == nil)
        #expect(store.registrationSignature(activityType: "ShipmentActivity") == nil)
    }

    @Test func clear_isNoOp_whenAlreadyEmpty() {
        let (store, _) = makeStore()
        store.clearAll()
        #expect(store.registrationSignature(activityType: "Any") == nil)
    }

    @Test func setSignature_afterClear_persistsCorrectly() {
        let (store, _) = makeStore()
        store.setRegistrationSignature(activityType: "OrderActivity", signature: "old|u")
        store.clearAll()
        store.setRegistrationSignature(activityType: "OrderActivity", signature: "new|u")
        #expect(store.registrationSignature(activityType: "OrderActivity") == "new|u")
    }

    @Test func clearRegistrationSignature_removesOnlyThatKey() {
        let (store, _) = makeStore()
        store.setRegistrationSignature(activityType: "OrderActivity", signature: "a|u")
        store.setRegistrationSignature(activityType: "instance:i1", signature: "dev|tok")
        store.clearRegistrationSignature(activityType: "instance:i1")
        #expect(store.registrationSignature(activityType: "instance:i1") == nil)
        #expect(store.registrationSignature(activityType: "OrderActivity") == "a|u")
    }

    @Test func clear_leavesUnrelatedKeysIntact() {
        let kv = InMemoryKeyValueStorage()
        kv.setString("device-token-abc", forKey: .pushDeviceToken)
        let store = KeyValueLiveActivityTokenStore(storage: kv)
        store.setRegistrationSignature(activityType: "OrderActivity", signature: "aaa|u")
        store.clearAll()
        // clearAll must only remove our own key, not wipe the shared store.
        #expect(kv.string(.pushDeviceToken) == "device-token-abc")
    }
}

// MARK: - Delivered dedup markers (TTL-bounded, separate map)

struct LiveActivityDeliveredMarkerTests {
    private let ttl: TimeInterval = 7 * 24 * 60 * 60

    @Test func freshMarker_isDeduped() {
        let (store, _) = makeStore()
        #expect(store.hasFreshDeliveredMarker("d1", ttl: ttl) == false)
        store.setDeliveredMarker("d1", at: Date())
        #expect(store.hasFreshDeliveredMarker("d1", ttl: ttl) == true)
    }

    @Test func expiredMarker_isNotFresh() {
        let (store, _) = makeStore()
        store.setDeliveredMarker("d1", at: Date(timeIntervalSinceNow: -(ttl + 60)))
        #expect(store.hasFreshDeliveredMarker("d1", ttl: ttl) == false)
    }

    @Test func expiredMarker_isPrunedFromStorage() {
        let (store, kv) = makeStore()
        store.setDeliveredMarker("old", at: Date(timeIntervalSinceNow: -(ttl + 60)))
        store.setDeliveredMarker("new", at: Date())
        // First delivered-marker access lazily prunes expired entries and persists the result.
        _ = store.hasFreshDeliveredMarker("new", ttl: ttl)
        // A fresh store over the same backing sees only the surviving marker.
        let reopened = KeyValueLiveActivityTokenStore(storage: kv)
        #expect(reopened.hasFreshDeliveredMarker("new", ttl: ttl) == true)
        #expect(reopened.hasFreshDeliveredMarker("old", ttl: ttl) == false)
    }

    @Test func deliveredMarkers_areIsolatedFromRegistrationMap() {
        let (store, _) = makeStore()
        store.setDeliveredMarker("d1", at: Date())
        store.setRegistrationSignature(activityType: "OrderActivity", signature: "sig|u")
        // Delivery markers live in a separate map: registration lookups never see them.
        #expect(store.registrationSignature(activityType: "d1") == nil)
        #expect(store.allRegistrationKeys() == ["OrderActivity"])
    }

    @Test func clearAll_dropsDeliveredMarkers() {
        let (store, _) = makeStore()
        store.setDeliveredMarker("d1", at: Date())
        store.clearAll()
        #expect(store.hasFreshDeliveredMarker("d1", ttl: ttl) == false)
    }
}
