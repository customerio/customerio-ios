@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation
import Testing

/// CoreLocation re-delivers the same `CLMonitor` event two to three times on device: identical
/// identifier, state and `date`, no diagnostic flags. Measured on every real drive; never seen on the
/// simulator. `CLMonitorGeofenceMonitor.process(event:)` has exactly one defence against it — the
/// stored per-region baseline, consulted through `storage.recordMonitorEvent(_:forIdentifier:)`
/// with no event identity attached.
///
/// For a business fence that is enough: the first copy advances the baseline and stops, so the
/// second reads as no change. For the movement trigger it is a race. The first exit copy starts a
/// movement pass that re-centres the trigger and re-seeds its baseline to "inside". A second copy
/// arriving *before* that re-seed is dropped; one arriving *after* it looks like a brand-new exit and
/// starts a second movement pass and sync. On the recorded drives the second copy won that race by
/// 4–9 ms every time. Nothing guarantees it.
///
/// `process(event:)` is private and `CLMonitor.Event` has no accessible initialiser, so the wrapper
/// cannot be driven from a test on this branch. These tests exercise the one call it makes to decide,
/// with the same arguments it passes, in the order the OS and the movement pass produce them.
@Suite("CLMonitor duplicate callback race")
struct CLMonitorDuplicateCallbackRaceTests {
    private let trigger = GeofenceConstants.movementTriggerIdentifier
    private let types: Set<GeofenceTransition> = [.enter, .exit]

    // Relative timeline of one movement exit as recorded on device, in seconds.
    private let registeredAt = Date(timeIntervalSince1970: 1_000_000)
    private let eventDate = Date(timeIntervalSince1970: 1_000_060.107) // CLMonitor.Event.date, shared by every copy
    private let firstCopyAt = Date(timeIntervalSince1970: 1_000_060.219)
    private let secondCopyAt = Date(timeIntervalSince1970: 1_000_060.232)
    private let reseedAt = Date(timeIntervalSince1970: 1_000_060.238)

    private func makeStorage() -> (GeofenceStorage, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (GeofenceStorage(fileManager: .default, directoryURL: dir), dir)
    }

    /// The trigger registered around the device and seeded inside, as `startMonitoring` does.
    private func registerTrigger(_ storage: GeofenceStorage, center: LocationData, at now: Date) async {
        await storage.recordMonitorRegistration(
            identifier: trigger, transitionTypes: types, initialState: .enter,
            center: center, radius: 1000, now: now
        )
    }

    @Test("Second copy lands before the re-seed: dropped, as on every recorded drive")
    func redeliveredExit_beforeReseed_expectSuppressed() async {
        let (storage, dir) = makeStorage()
        defer { try? FileManager.default.removeItem(at: dir) }
        await registerTrigger(storage, center: LocationData(latitude: 10, longitude: 20), at: registeredAt)

        #expect(await storage.recordMonitorEvent(.exit, forIdentifier: trigger, now: firstCopyAt) == .deliver)
        #expect(await storage.recordMonitorEvent(.exit, forIdentifier: trigger, now: secondCopyAt) == .suppressedNoChange)
    }

    @Test("Second copy lands after the re-seed: the same OS event is delivered as a new crossing")
    func redeliveredExit_afterReseed_expectSuppressed() async {
        let (storage, dir) = makeStorage()
        defer { try? FileManager.default.removeItem(at: dir) }
        await registerTrigger(storage, center: LocationData(latitude: 10, longitude: 20), at: registeredAt)

        #expect(await storage.recordMonitorEvent(.exit, forIdentifier: trigger, now: firstCopyAt) == .deliver)
        // The movement pass the first copy started re-centres the trigger on the new position.
        await registerTrigger(storage, center: LocationData(latitude: 10.01, longitude: 20.01), at: reseedAt)

        // Same event, re-delivered by CoreLocation. It already produced a movement pass; it must not
        // produce another. On this branch the outcome is `.deliver`.
        let outcome = await storage.recordMonitorEvent(.exit, forIdentifier: trigger, now: secondCopyAt)
        #expect(outcome != .deliver, "a re-delivered OS event was accepted as a second exit: \(outcome)")
    }

    @Test("Given the OS event's own date, the baseline can tell the copy is stale — the wrapper never passes it")
    func redeliveredExit_afterReseed_givenEventDate_expectSuppressed() async {
        let (storage, dir) = makeStorage()
        defer { try? FileManager.default.removeItem(at: dir) }
        await registerTrigger(storage, center: LocationData(latitude: 10, longitude: 20), at: registeredAt)

        #expect(await storage.recordMonitorEvent(.exit, forIdentifier: trigger, onlyIfBaselinePredates: eventDate, now: firstCopyAt) == .deliver)
        await registerTrigger(storage, center: LocationData(latitude: 10.01, longitude: 20.01), at: reseedAt)

        let outcome = await storage.recordMonitorEvent(.exit, forIdentifier: trigger, onlyIfBaselinePredates: eventDate, now: secondCopyAt)
        #expect(outcome == .suppressedNewerBaseline)
    }
}
