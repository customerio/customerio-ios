@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation
import SharedTests
import Testing

/// The composition stands up, and the SDK is actually listening at the OS seam.
///
/// The failure is otherwise silent: if the wrapper never subscribes to the condition stream, every
/// replayed crossing goes nowhere and each drive reads as "the SDK stopped reacting".
@Suite("Replay composition", .serialized, .enabled(if: ReplayRuntime.isMonitorAvailable))
@MainActor
struct ReplayCompositionTests {
    @Test
    func composeAndWire_expectTheSdkListeningAtTheOsSeam() async throws {
        guard #available(iOS 17.0, *) else {
            // Unreachable: the trait above skips this runtime. Recorded, not returned quietly,
            // so it cannot pass having asserted nothing.
            Issue.record("replay needs iOS 17+ — the availability trait should have skipped")
            return
        }

        let harness = await ReplayHarness.withTail { () -> ReplayHarness in
            let harness = ReplayHarness()
            await harness.wireMonitor()
            return harness
        }

        #expect(
            harness.conditionMonitor.hasSubscriber,
            "the SDK never subscribed to the OS condition stream — every replayed crossing would go nowhere"
        )
        // Delivered after the subscription is asserted, so this can fail: if the wrapper's consume
        // task is not attached yet, the monitor counts the event as dropped.
        harness.conditionMonitor.deliver(identifier: "A", state: .satisfied, at: Date())
        #expect(
            harness.conditionMonitor.deliveredWithNoSubscriber == 0,
            "a crossing delivered after wiring went nowhere — the SDK was not listening yet"
        )
    }
}
