@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation
import SharedTests
import Testing

@Suite("Replay composition", .serialized, .enabled(if: ReplayRuntime.isMonitorAvailable))
@MainActor
struct ReplayCompositionTests {
    @Test
    func composeAndWire_expectTheSdkListeningAtTheOsSeam() async throws {
        guard #available(iOS 17.0, *) else {
            // Recorded, not a quiet return, so it can't pass having asserted nothing.
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
        harness.conditionMonitor.deliver(identifier: "A", state: .satisfied, at: Date())
        #expect(
            harness.conditionMonitor.deliveredWithNoSubscriber == 0,
            "a crossing delivered after wiring went nowhere — the SDK was not listening yet"
        )
    }
}
