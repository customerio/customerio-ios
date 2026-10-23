@testable import CioLocationGeofence
import CoreLocation
import Foundation
import Testing

/// What a unit test can establish about the continuous wait: the opt-in gate, cancellation and units.
/// Whether a parked wait fires on time through device sleep needs a physical device: neither the
/// simulator nor a test host sleeps while a test runs, so awake and continuous time cannot diverge here.
@Suite("Geofence continuous wait")
@MainActor
struct GeofenceContinuousWaitTests {
    @Test
    func ifOptedIn_whenNoContinuousWaitExists_thenNoCollectionIsBuilt() {
        // Opted in, with the background mode declared: only the missing wait keeps the experiment off.
        let owner = PendingDwellCollectionOwner.ifOptedIn(optedIn, makeManager: { UnusedManager() }, sleep: nil)
        let built = owner != nil
        #expect(!built)
    }

    @Test
    func ifOptedIn_whenDefaultWaitIsUsed_thenBuiltExactlyWhereContinuousWaitExists() {
        let owner = PendingDwellCollectionOwner.ifOptedIn(optedIn, makeManager: { UnusedManager() })
        let built = owner != nil
        if #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) {
            #expect(built)
        } else {
            #expect(!built)
        }
    }

    /// A deadline or cap replaced long before it is due must not hold its task until then.
    @Test
    func continuousWait_whenCancelled_thenThrowsWithoutWaitingOutItsDelay() async throws {
        let wait = try #require(GeofenceContinuousWait.continuous)
        let waiter = Task { try await wait(3600 * 1000000000) }
        waiter.cancel()
        await #expect(throws: CancellationError.self) { try await waiter.value }
    }

    /// Nanoseconds in, at least that span out on the clock lease deadlines are read on.
    @Test
    func continuousWait_whenItReturns_thenItsDelayHasPassedOnTheGeofenceClock() async throws {
        let wait = try #require(GeofenceContinuousWait.continuous)
        let clock = SystemGeofenceClock()
        let start = clock.read().uptime
        try await wait(50000000)
        // A units slip, microseconds for nanoseconds say, would return a thousand times early.
        #expect(clock.read().uptime - start >= 0.049)
    }

    private var optedIn: PendingDwellCollectionOptIn {
        PendingDwellCollectionOptIn(infoValue: { key in
            switch key {
            case PendingDwellCollectionOptIn.key: return true
            case "UIBackgroundModes": return ["location"] as [String]
            default: return nil
            }
        })
    }
}

/// Never started: these tests build no session.
private final class UnusedManager: PendingDwellLocationManaging {
    var desiredAccuracy: CLLocationAccuracy = 0
    var distanceFilter: CLLocationDistance = 0
    var pausesLocationUpdatesAutomatically = true
    var allowsBackgroundLocationUpdates = false
    var onActivity: (@MainActor (PendingDwellSessionCallback) -> Void)?
    func startUpdatingLocation() {}
    func stopUpdatingLocation() {}
}
