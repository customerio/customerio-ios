@testable import CioInternalCommon
import Dispatch
import Foundation
import Testing

// MARK: - Recording stub

/// Minimal `CustomerIOInstance` stub that records the order of buffered calls
/// during drain tests. Only the methods exercised by these tests are
/// implemented; the rest no-op.
private final class RecordingInstance: CustomerIOInstance, @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [String] = []

    var events: [String] {
        lock.withLock { _events }
    }

    private func record(_ event: String) {
        lock.withLock { _events.append(event) }
    }

    // MARK: CustomerIOInstance — only the calls used in tests below are real

    var profileAttributes: [String: Any] = [:]
    func setProfileAttributes(_ attributes: [String: Any]) {
        record("setProfileAttributes:\(attributes.keys.sorted().joined(separator: ","))")
    }

    func identify(userId: String, traits: [String: Any]?) {
        record("identify:\(userId)")
    }

    func identify<RequestBody: Codable>(userId: String, traits: RequestBody?) {
        record("identifyCodable:\(userId)")
    }

    func clearIdentify() {
        record("clearIdentify")
    }

    var deviceAttributes: [String: Any] = [:]
    func setDeviceAttributes(_ attributes: [String: Any]) {
        record("setDeviceAttributes")
    }

    var registeredDeviceToken: String? {
        nil
    }

    func registerDeviceToken(_ deviceToken: String) {
        record("registerDeviceToken:\(deviceToken)")
    }

    func deleteDeviceToken() {
        record("deleteDeviceToken")
    }

    func track(name: String, properties: [String: Any]?) {
        record("track:\(name)")
    }

    func track<RequestBody: Codable>(name: String, properties: RequestBody?) {
        record("trackCodable:\(name)")
    }

    func screen(title: String, properties: [String: Any]?) {
        record("screen:\(title)")
    }

    func screen<RequestBody: Codable>(title: String, properties: RequestBody?) {
        record("screenCodable:\(title)")
    }

    func trackMetric(deliveryID: String, event: Metric, deviceToken: String) {
        record("trackMetric:\(deliveryID)")
    }
}

// MARK: - Buffer state and ordering

struct PreInitEventBufferTests {
    private func makeBuffer(capacity: Int = 100) -> PreInitEventBuffer {
        // Inject a nil-returning logger provider so tests don't depend on the
        // shared DI graph state (which may or may not have a logger registered
        // depending on test-run order).
        PreInitEventBuffer(capacity: capacity, loggerProvider: { nil })
    }

    @Test func enqueueAccumulatesWhileBuffering() {
        let buffer = makeBuffer()
        buffer.enqueue { _ in }
        buffer.enqueue { _ in }
        buffer.enqueue { _ in }
        #expect(buffer.bufferedCount == 3)
        #expect(buffer.isReady == false)
    }

    @Test func drainReplaysInOrder() {
        let buffer = makeBuffer()
        let recorder = RecordingInstance()
        buffer.enqueue { $0.track(name: "one", properties: nil) }
        buffer.enqueue { $0.identify(userId: "alice", traits: nil) }
        buffer.enqueue { $0.screen(title: "Home", properties: nil) }
        buffer.transitionToReady(recorder)

        #expect(recorder.events == [
            "track:one",
            "identify:alice",
            "screen:Home"
        ])
        #expect(buffer.isReady == true)
        #expect(buffer.bufferedCount == 0)
    }

    @Test func postReadyEnqueueExecutesImmediately() {
        let buffer = makeBuffer()
        let recorder = RecordingInstance()
        buffer.transitionToReady(recorder)
        buffer.enqueue { $0.track(name: "after", properties: nil) }
        #expect(recorder.events == ["track:after"])
        #expect(buffer.bufferedCount == 0)
    }

    @Test func overflowDropsMostRecent() {
        let buffer = makeBuffer(capacity: 3)
        let recorder = RecordingInstance()

        // Enqueue 5 events. The first 3 should be retained; events 4 and 5 dropped.
        for index in 0 ..< 5 {
            buffer.enqueue { $0.track(name: "event-\(index)", properties: nil) }
        }
        #expect(buffer.bufferedCount == 3)
        #expect(buffer.droppedEventCount == 2)

        buffer.transitionToReady(recorder)

        #expect(recorder.events == [
            "track:event-0",
            "track:event-1",
            "track:event-2"
        ])
        // Drop counter is reset after drain so subsequent overflow accounting
        // starts clean.
        #expect(buffer.droppedEventCount == 0)
    }

    @Test func transitionToReadyOnEmptyBufferIsNoop() {
        let buffer = makeBuffer()
        let recorder = RecordingInstance()
        buffer.transitionToReady(recorder)
        #expect(buffer.isReady == true)
        #expect(recorder.events.isEmpty)
    }

    @Test func transitionToReadyCalledTwiceIsSafe() {
        let buffer = makeBuffer()
        let recorder1 = RecordingInstance()
        let recorder2 = RecordingInstance()
        buffer.enqueue { $0.track(name: "first", properties: nil) }
        buffer.transitionToReady(recorder1)
        // Second call should be a no-op — events were already drained to recorder1.
        buffer.transitionToReady(recorder2)
        #expect(recorder1.events == ["track:first"])
        #expect(recorder2.events.isEmpty)
    }

    @Test func bufferSurvivesAcrossEnqueueCycles() {
        // If "initialize" never actually runs (in real terms, that means
        // transitionToReady is never called), the buffer should sit at cap
        // and continue dropping new events without crashing or growing.
        let buffer = makeBuffer(capacity: 2)
        buffer.enqueue { _ in }
        buffer.enqueue { _ in }
        buffer.enqueue { _ in }
        buffer.enqueue { _ in }
        #expect(buffer.bufferedCount == 2)
        #expect(buffer.droppedEventCount == 2)
    }

    @Test func enqueueDuringDrainIsPickedUp() {
        // Reentrancy: while a buffered block is executing, the block itself
        // enqueues another event. The newly-enqueued event must drain
        // (either picked up by the same drain loop because the buffer is in
        // .draining state, or executed immediately if state already advanced
        // to .ready). Either way, both events must end up recorded in order.
        let buffer = makeBuffer()
        let recorder = RecordingInstance()
        buffer.enqueue { impl in
            impl.track(name: "outer", properties: nil)
        }
        // Reentrant enqueue from inside a block, captured into a separate
        // buffer reference so the closure is non-self-referential.
        let bufferRef = buffer
        buffer.enqueue { _ in
            bufferRef.enqueue { $0.track(name: "inner", properties: nil) }
        }
        buffer.transitionToReady(recorder)
        #expect(recorder.events == ["track:outer", "track:inner"])
    }

    @Test func drainingStateEnforcesCapacity() {
        // While in .draining (i.e. the drain is replaying outer blocks), any
        // reentrant enqueue must respect the same capacity as .buffering.
        // Without this guarantee, a launch-time burst racing the drain could
        // grow `pending` past the documented bound and bypass drop accounting.
        let buffer = makeBuffer(capacity: 2)
        let recorder = RecordingInstance()
        let bufferRef = buffer

        // First block triggers 4 reentrant enqueues while the buffer is in
        // .draining. Only the first 2 should be retained; the remaining 2
        // must be counted as drops.
        buffer.enqueue { impl in
            impl.track(name: "outer", properties: nil)
            for i in 0 ..< 4 {
                bufferRef.enqueue { $0.track(name: "inner-\(i)", properties: nil) }
            }
        }
        buffer.transitionToReady(recorder)

        #expect(recorder.events == [
            "track:outer",
            "track:inner-0",
            "track:inner-1"
        ])
        // 2 dropped during the draining phase; counter is reset after drain.
        #expect(buffer.droppedEventCount == 0)
    }

    @Test func concurrentEnqueuesArePreservedUpToCap() {
        let buffer = makeBuffer(capacity: 200)
        let recorder = RecordingInstance()

        // Spin up several threads, each enqueueing N events. Total enqueued
        // must equal `bufferedCount` (no drops below cap).
        let group = DispatchGroup()
        let perThread = 25
        let threadCount = 4
        for thread in 0 ..< threadCount {
            group.enter()
            DispatchQueue.global().async {
                for i in 0 ..< perThread {
                    buffer.enqueue { $0.track(name: "t\(thread)-\(i)", properties: nil) }
                }
                group.leave()
            }
        }
        group.wait()

        #expect(buffer.bufferedCount == threadCount * perThread)
        buffer.transitionToReady(recorder)
        #expect(recorder.events.count == threadCount * perThread)
    }
}
