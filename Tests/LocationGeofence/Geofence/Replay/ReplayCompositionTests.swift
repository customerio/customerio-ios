@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation
import SharedTests
import Testing

/// The composition stands up, and the SDK is actually listening at the OS seam.
///
/// Worth a case of its own because the failure it catches is silent. If the wrapper never
/// subscribes to the condition stream, every crossing a replay pushes goes nowhere: each scenario
/// reports no decisions at all, and the drive reads as "the SDK stopped reacting" rather than
/// "nothing was ever wired up". That is the shape of failure this whole harness exists to refuse.
@Suite("Replay composition", .serialized, .enabled(if: ReplayRuntime.isMonitorAvailable))
@MainActor
struct ReplayCompositionTests {
    @Test
    func composeAndWire_expectTheSdkListeningAtTheOsSeam() async throws {
        guard #available(iOS 17.0, *) else {
            // Unreachable: the trait above skips this runtime. Recorded rather than returned
            // quietly, because a silent return is a green test that asserted nothing.
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
        #expect(harness.conditionMonitor.deliveredWithNoSubscriber == 0)
    }
}
