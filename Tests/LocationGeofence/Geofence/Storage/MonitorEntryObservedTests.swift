@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation
import SharedTests
import Testing

/// Whether a delivered CLMonitor ENTER is a crossing since registration, or may be the OS
/// correcting an `assuming:` the SDK could not back with a fix. The ENTER is delivered either way;
/// only the visit it starts differs.
@Suite("GeofenceStorage entry observation")
struct MonitorEntryObservedTests {
    private let center = LocationData(latitude: 10, longitude: 20)

    private func withStorage(_ body: (GeofenceStorage) async -> Void) async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        await body(GeofenceStorage(fileManager: .default, directoryURL: dir))
    }

    private func register(
        _ storage: GeofenceStorage,
        initialState: GeofenceTransition = .exit,
        observed: Bool,
        radius: Double = 100,
        forceReseed: Bool = false
    ) async {
        await storage.recordMonitorRegistration(
            identifier: "geo_1", transitionTypes: [.enter, .exit], initialState: initialState,
            center: center, radius: radius, forceReseed: forceReseed, initialStateObserved: observed
        )
    }

    private func record(_ storage: GeofenceStorage, _ transition: GeofenceTransition) async -> (outcome: GeofenceMonitorEventOutcome, entryObserved: Bool) {
        await storage.recordMonitorTransition(transition, forIdentifier: "geo_1")
    }

    @Test
    func recordMonitorTransition_givenAssumedOutside_expectEnterDeliveredButNotObserved() async {
        await withStorage { storage in
            await register(storage, observed: false)

            let result = await record(storage, .enter)

            #expect(result.outcome == .deliver)
            #expect(result.entryObserved == false)
        }
    }

    @Test
    func recordMonitorTransition_givenSettledOutside_expectEnterObserved() async {
        await withStorage { storage in
            await register(storage, observed: true)

            let result = await record(storage, .enter)

            #expect(result.outcome == .deliver)
            #expect(result.entryObserved == true)
        }
    }

    /// An OS event matching the assumption may be `CLMonitor` echoing it back, so it proves nothing.
    @Test
    func recordMonitorTransition_givenAssumedOutsideEchoed_expectLaterEnterStillNotObserved() async {
        await withStorage { storage in
            await register(storage, observed: false)

            #expect(await record(storage, .exit).outcome == .suppressedNoChange)
            let result = await record(storage, .enter)

            #expect(result.outcome == .deliver)
            #expect(result.entryObserved == false)
        }
    }

    /// Once the OS reports leaving, the device was outside since registration, so the next ENTER
    /// is a crossing.
    @Test
    func recordMonitorTransition_givenObservedExitAfterAssumedEntry_expectNextEnterObserved() async {
        await withStorage { storage in
            await register(storage, observed: false)
            #expect(await record(storage, .enter).entryObserved == false)
            #expect(await record(storage, .exit).outcome == .deliver)

            let result = await record(storage, .enter)

            #expect(result.outcome == .deliver)
            #expect(result.entryObserved == true)
        }
    }

    /// Wrongly assumed inside: the OS corrects with an EXIT, and that correction IS an observation.
    @Test
    func recordMonitorTransition_givenAssumedInsideCorrected_expectNextEnterObserved() async {
        await withStorage { storage in
            await register(storage, initialState: .enter, observed: false)
            #expect(await record(storage, .exit).outcome == .deliver)

            #expect(await record(storage, .enter).entryObserved == true)
        }
    }

    /// An unchanged re-registration keeps the baseline, and with it what is known about it: a
    /// fresh fix at the re-add does not retroactively settle the state preserved from before.
    @Test
    func recordMonitorRegistration_givenUnchangedReRegistration_expectObservationPreserved() async {
        await withStorage { storage in
            await register(storage, observed: false)
            await register(storage, observed: true)

            #expect(await record(storage, .enter).entryObserved == false)
        }
    }

    @Test
    func recordMonitorRegistration_givenForcedReseedWithoutFix_expectObservationDropped() async {
        await withStorage { storage in
            await register(storage, observed: true)
            // The OS stopped monitoring: the device may have moved while unwatched.
            await register(storage, observed: false, forceReseed: true)

            #expect(await record(storage, .enter).entryObserved == false)
        }
    }

    @Test
    func recordMonitorRegistration_givenChangedCircle_expectReseededObservation() async {
        await withStorage { storage in
            await register(storage, observed: false)
            await register(storage, observed: true, radius: 150)

            #expect(await record(storage, .enter).entryObserved == true)
        }
    }

    /// Records persisted before the field say nothing about how their state was learned.
    @Test
    func recordMonitorTransition_givenLegacyRecord_expectEnterNotObserved() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let legacy = #"{"monitorRegionRecords":{"geo_1":{"lastState":"exit","transitionTypes":["enter","exit"]}}}"#
        try Data(legacy.utf8).write(to: dir.appendingPathComponent("geofenceState.json"))
        let storage = GeofenceStorage(fileManager: .default, directoryURL: dir)

        let result = await storage.recordMonitorTransition(.enter, forIdentifier: "geo_1")

        #expect(result.outcome == .deliver)
        #expect(result.entryObserved == false)
    }
}
