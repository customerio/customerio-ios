import Foundation
import Testing

@testable import CioLiveActivities

struct LiveActivityRegistrarTests {
    private struct Harness {
        let cap: TrackCapture
        let store: FakeTokenStore
        let identity: LiveActivityIdentity
        let registrar: LiveActivityRegistrar
    }

    private func makeHarness() -> Harness {
        let cap = TrackCapture()
        let store = FakeTokenStore()
        let identity = LiveActivityIdentity()
        let reporter = LiveActivityReporter(
            track: { name, props in cap.record(name, props) },
            currentUserId: { identity.userId },
            deviceToken: { identity.deviceToken },
            logger: NoopLogger()
        )
        let registrar = LiveActivityRegistrar(identity: identity, store: store, reporter: reporter)
        return Harness(cap: cap, store: store, identity: identity, registrar: registrar)
    }

    // token = Data([0xaa, 0xbb]) → "aabb"
    private let token = Data([0xAA, 0xBB])

    @Test func pushToStart_whileAnonymous_isDeferred_notStored() {
        let h = makeHarness()
        h.identity.deviceToken = "dev"
        h.registrar.handlePushToStartToken(notificationType: "t", attributesType: "A", token: token)
        #expect(h.cap.isEmpty)
        #expect(h.store.signatures.isEmpty)
    }

    @Test func pushToStart_refires_onIdentify() {
        let h = makeHarness()
        h.identity.deviceToken = "dev"
        h.registrar.handlePushToStartToken(notificationType: "t", attributesType: "A", token: token)
        #expect(h.cap.isEmpty)

        h.identity.userId = "user-1"
        h.registrar.reevaluate()
        #expect(h.cap.count == 1)
        #expect(h.store.signatures["t"] == "dev|aabb|user-1")
    }

    @Test func pushToStart_deferred_untilDeviceTokenArrives() {
        let h = makeHarness()
        h.identity.userId = "user-1"
        h.registrar.handlePushToStartToken(notificationType: "t", attributesType: "A", token: token)
        #expect(h.cap.isEmpty)

        h.identity.deviceToken = "dev"
        h.registrar.reevaluate()
        #expect(h.cap.count == 1)
    }

    @Test func pushToStart_sameTokenAndUser_isNotResent() {
        let h = makeHarness()
        h.identity.userId = "user-1"
        h.identity.deviceToken = "dev"
        h.registrar.handlePushToStartToken(notificationType: "t", attributesType: "A", token: token)
        #expect(h.cap.count == 1)

        h.registrar.reevaluate()
        h.registrar.reevaluate()
        #expect(h.cap.count == 1)
    }

    @Test func pushToStart_newUser_reRegisters() {
        let h = makeHarness()
        h.identity.userId = "user-1"
        h.identity.deviceToken = "dev"
        h.registrar.handlePushToStartToken(notificationType: "t", attributesType: "A", token: token)
        #expect(h.cap.count == 1)

        h.identity.userId = "user-2"
        h.registrar.reevaluate()
        #expect(h.cap.count == 2)
        #expect(h.store.signatures["t"] == "dev|aabb|user-2")
    }

    @Test func pushToStart_deviceTokenRotation_reRegisters() {
        let h = makeHarness()
        h.identity.userId = "user-1"
        h.identity.deviceToken = "dev"
        h.registrar.handlePushToStartToken(notificationType: "t", attributesType: "A", token: token)
        #expect(h.cap.count == 1)

        // Device token rotates (same push-to-start token + user): must re-register against the
        // new device rather than dedup as unchanged.
        h.identity.deviceToken = "dev2"
        h.registrar.reevaluate()
        #expect(h.cap.count == 2)
        #expect(h.store.signatures["t"] == "dev2|aabb|user-1")
    }

    @Test func instanceToken_dedupsByToken_reSendsOnChange() {
        let h = makeHarness()
        h.identity.userId = "user-1"
        h.identity.deviceToken = "dev"

        h.registrar.handleInstanceToken(notificationType: "t", instanceUUID: "i1", token: Data([0x01]))
        #expect(h.cap.count == 1)

        // Same token again — deduped.
        h.registrar.handleInstanceToken(notificationType: "t", instanceUUID: "i1", token: Data([0x01]))
        #expect(h.cap.count == 1)

        // Rotated token — re-sent.
        h.registrar.handleInstanceToken(notificationType: "t", instanceUUID: "i1", token: Data([0x02]))
        #expect(h.cap.count == 2)
    }

    @Test func instanceToken_concurrentSameToken_sendsExactlyOnce() async {
        let h = makeHarness()
        h.identity.userId = "user-1"
        h.identity.deviceToken = "dev"
        let registrar = h.registrar
        let token = Data([0x0A, 0x0B])

        // Many concurrent observers reporting the same instance token must not each send.
        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 100 {
                group.addTask {
                    registrar.handleInstanceToken(notificationType: "t", instanceUUID: "i1", token: token)
                }
            }
        }
        #expect(h.cap.count == 1)
    }

    @Test func instanceToken_notResent_onRelaunch_withPersistedStore() {
        // Shared store simulates persistence across launches; each registrar is a fresh process.
        let sharedStore = FakeTokenStore()
        // Each call is a fresh "process": new in-memory registrar/identity (identified, with a
        // device token) over the SAME persisted store.
        func makeRegistrar() -> (LiveActivityRegistrar, TrackCapture) {
            let cap = TrackCapture()
            let identity = LiveActivityIdentity()
            identity.userId = "user-1"
            identity.deviceToken = "dev"
            let reporter = LiveActivityReporter(
                track: { name, props in cap.record(name, props) },
                currentUserId: { identity.userId },
                deviceToken: { identity.deviceToken },
                logger: NoopLogger()
            )
            return (LiveActivityRegistrar(identity: identity, store: sharedStore, reporter: reporter), cap)
        }

        // Launch 1: observe instance token → sends once.
        let (r1, cap1) = makeRegistrar()
        r1.handleInstanceToken(notificationType: "t", instanceUUID: "i1", token: token)
        #expect(cap1.count == 1)

        // Relaunch: fresh in-memory registrar, SAME persisted store, re-observe the same token.
        let (r2, cap2) = makeRegistrar()
        r2.handleInstanceToken(notificationType: "t", instanceUUID: "i1", token: token)
        #expect(cap2.isEmpty) // persisted signature ⇒ no re-send
    }

    @Test func instanceToken_reSent_afterEnded() {
        let h = makeHarness()
        h.identity.userId = "user-1"
        h.identity.deviceToken = "dev"
        h.registrar.handleInstanceToken(notificationType: "t", instanceUUID: "i1", token: token)
        #expect(h.cap.count == 1)

        // Ending clears the persisted instance signature, so the same token re-registers after.
        h.registrar.handleActivityEnded(instanceUUID: "i1")
        h.registrar.handleInstanceToken(notificationType: "t", instanceUUID: "i1", token: token)
        #expect(h.cap.count == 2)
    }

    @Test func handleReset_clearsSignatures() {
        let h = makeHarness()
        h.identity.userId = "user-1"
        h.identity.deviceToken = "dev"
        h.registrar.handlePushToStartToken(notificationType: "t", attributesType: "A", token: token)
        #expect(h.store.signatures.isEmpty == false)

        h.registrar.handleReset()
        #expect(h.store.signatures.isEmpty)
    }

    @Test func pushToStart_reRegisters_afterResetThenReidentify() {
        let h = makeHarness()
        h.identity.userId = "user-1"
        h.identity.deviceToken = "dev"
        h.registrar.handlePushToStartToken(notificationType: "t", attributesType: "A", token: token)
        #expect(h.cap.count == 1)

        // Logout: reset clears signatures but keeps the per-app push-to-start token pending.
        h.identity.userId = nil
        h.registrar.handleReset()

        // Re-login: the retained token + cleared signature must re-register (the device bug we hit).
        h.identity.userId = "user-1"
        h.registrar.reevaluate()
        #expect(h.cap.count == 2)
        #expect(h.store.signatures["t"] == "dev|aabb|user-1")
    }
}
