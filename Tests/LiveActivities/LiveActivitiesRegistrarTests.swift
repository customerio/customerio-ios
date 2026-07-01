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
        #expect(h.store.signatures["t"] == "aabb|user-1")
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
        #expect(h.store.signatures["t"] == "aabb|user-2")
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
        #expect(h.store.signatures["t"] == "aabb|user-1")
    }
}
