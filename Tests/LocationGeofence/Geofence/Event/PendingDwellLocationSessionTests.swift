@testable import CioLocationGeofence
import CoreLocation
import Foundation
import Testing

@Suite("Pending dwell location session")
@MainActor
struct PendingDwellLocationSessionTests {
    @Test(arguments: PendingDwellIneligibleSetup.allCases)
    func start_whenAnyGateIsClosed_thenNoManagerIsEverCreated(setup: PendingDwellIneligibleSetup) {
        let env = SessionEnv()
        setup.apply(to: env)
        let session = env.make()

        #expect(!session.isEligible)
        #expect(!session.start())
        // No manager: background updates were never enabled, so nothing could crash, prompt or run.
        #expect(env.managers.isEmpty)
    }

    @Test
    func diagnostics_whenSessionCallsBackRepeatsOrStops_thenRecordsEachKindOnlyUnderItsOwnRun() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = DwellDiagnosticJournal(directory: directory, isEnabled: { true })
        let recorder = DwellDiagnosticRecorder(journal: journal, isEnabled: true, now: { 10 })
        let env = SessionEnv(), session = env.make(diagnosticRecorder: recorder)
        #expect(session.start())
        #expect(session.start())
        let first = try #require(env.managers.first)
        // First the authorization callback Core Location delivers once a manager exists, then the others.
        first.onActivity?(.authorizationChange)
        first.onActivity?(.locationUpdate)
        first.onActivity?(.locationError)
        session.stop()
        session.stop()
        await recorder.drain()
        #expect(await journal.snapshot()?.map(\.event) == [
            .sessionStarted, .sessionAuthorizationCallback, .sessionLocationCallback, .sessionErrorCallback,
            .sessionStopped
        ])
        #expect(env.activityCount == 3, "every kind, the creation-time authorization callback included, reconciles")
        #expect(session.start())
        let second = try #require(env.managers.last)
        let callback = second.onActivity
        recorder.invalidateAndClear()
        callback?(.locationUpdate)
        session.stop()
        callback?(.authorizationChange)
        await recorder.drain()
        #expect(await journal.snapshot() == [], "late activity and stop must keep their retired run token")
        #expect(env.activityCount == 5, "diagnostics must not change the owner's existing activity path")
    }

    @Test
    func diagnostics_whenIdentityChangesMidRun_thenLateCallbacksRecordNothingButStillReconcile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = DwellDiagnosticJournal(directory: directory, isEnabled: { true })
        var identity: GeofenceIdentity? = GeofenceIdentity(userId: "person-a", version: 1, lineage: "lineage-a")
        let recorder = DwellDiagnosticRecorder(
            journal: journal, isEnabled: true, now: { 10 }, identityProvider: { identity }
        )
        let env = SessionEnv(), session = env.make(diagnosticRecorder: recorder)
        #expect(session.start())
        let manager = try #require(env.managers.first)
        manager.onActivity?(.authorizationChange)

        identity = GeofenceIdentity(userId: "person-b", version: 2, lineage: "lineage-b")
        manager.onActivity?(.locationUpdate)
        session.stop()
        await recorder.drain()

        // The new identity's owner check cleared the old history; nothing the old run reported joined the new.
        #expect(await journal.snapshot() == [])
        #expect(env.activityCount == 2, "an identity change must not silence the owner's reconcile")
        #expect(session.start())
        await recorder.drain()
        #expect(await journal.snapshot()?.map(\.event) == [.sessionStarted], "a new run records")
    }

    @Test
    func coreLocationManager_whenEachDelegateCallbackArrives_thenReportsItsOwnKind() {
        let manager = CoreLocationPendingDwellManager()
        var reported: [PendingDwellSessionCallback] = []
        manager.onActivity = { reported.append($0) }
        let caller = CLLocationManager()

        manager.locationManager(caller, didUpdateLocations: [CLLocation(latitude: 0, longitude: 0)])
        manager.locationManager(caller, didFailWithError: CLError(.locationUnknown))
        manager.locationManagerDidChangeAuthorization(caller)

        // Synchronous on the main actor, so Core Location's own creation-time callback cannot land in between.
        #expect(reported == [.locationUpdate, .locationError, .authorizationChange])
    }

    @Test
    func journal_whenAnEarlierBuildWroteWakeSession_thenItStillReadsBesideTheNewKinds() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = DwellDiagnosticJournal.fileURL(in: directory)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        // As the earlier experimental build wrote it: one session callback of unknown kind.
        let legacy = #"{"provider":"core_location","records":[{"atUptime":5,"event":"wakeSession"}],"version":1}"#
        try Data(legacy.utf8).write(to: file)
        let journal = DwellDiagnosticJournal(directory: directory, isEnabled: { true })
        let entry = try #require(DwellDiagnosticRecord(event: .sessionAuthorizationCallback, atUptime: 6))

        #expect(await journal.append(entry))
        #expect(await journal.snapshot()?.map(\.event) == [.wakeSession, .sessionAuthorizationCallback])
    }

    @Test
    func start_whenEligible_thenStartsOneLowPowerUnpausedBackgroundSession() throws {
        let env = SessionEnv()
        let session = env.make()

        #expect(session.start())
        #expect(session.start())

        let manager = try #require(env.managers.first)
        #expect(env.managers.count == 1)
        #expect(manager.startCalls == 1)
        // Read at the start call: no precise, pausing or foreground-only session ever runs.
        #expect(manager.settingsAtStart == .lowPowerBackground)
    }

    @Test
    func stop_thenStopsOnceClearsBackgroundAndRestartsWithAFreshManager() throws {
        let env = SessionEnv()
        let session = env.make()
        session.start()

        session.stop()
        session.stop()

        let first = try #require(env.managers.first)
        #expect(first.stopCalls == 1)
        #expect(!first.allowsBackgroundLocationUpdates)
        #expect(first.onActivity == nil)
        #expect(session.start())
        #expect(env.managers.count == 2)
    }

    @Test
    func start_whenAccessDropsWhileRunning_thenStopsTheRunningSession() throws {
        let env = SessionEnv()
        let session = env.make()
        session.start()

        env.access = GeofenceLocationAccess(delivery: .foregroundOnly, fullAccuracy: true)

        #expect(!session.start())
        #expect(!session.isRunning)
        #expect(try #require(env.managers.first).stopCalls == 1)
    }

    @Test
    func release_whileRunning_thenStopsUpdatesAndLateCallbacksReachNoOwner() throws {
        let env = SessionEnv()
        var session: PendingDwellLocationSession? = env.make()
        session?.start()
        let manager = try #require(env.managers.first)
        manager.onActivity?(.locationUpdate)
        #expect(env.activityCount == 1)

        weak var released = session
        session = nil

        // The manager's callback holds the session weakly, so nothing keeps it or its updates alive.
        #expect(released == nil)
        #expect(manager.stopCalls == 1)
        manager.onActivity?(.locationUpdate)
        #expect(env.activityCount == 1)
    }
}

enum PendingDwellIneligibleSetup: String, CaseIterable, Sendable {
    case notOptedIn, noLocationBackgroundMode, whenInUseOnly, reducedAccuracy, unknownAccess

    @MainActor
    fileprivate func apply(to env: SessionEnv) {
        switch self {
        case .notOptedIn: env.info[PendingDwellCollectionOptIn.key] = nil
        case .noLocationBackgroundMode: env.info["UIBackgroundModes"] = ["fetch", "remote-notification"]
        case .whenInUseOnly: env.access = GeofenceLocationAccess(delivery: .foregroundOnly, fullAccuracy: true)
        case .reducedAccuracy: env.access = GeofenceLocationAccess(delivery: .background, fullAccuracy: false)
        case .unknownAccess: env.access = nil
        }
    }
}

@MainActor
private final class SessionEnv {
    var info: [String: Any] = [PendingDwellCollectionOptIn.key: true, "UIBackgroundModes": ["location", "fetch"]]
    var access: GeofenceLocationAccess? = GeofenceLocationAccess(delivery: .background, fullAccuracy: true)
    private(set) var managers: [FakeLocationManager] = []
    private(set) var activityCount = 0

    func make(diagnosticRecorder: DwellDiagnosticRecorder? = nil) -> PendingDwellLocationSession {
        let info = self.info
        return PendingDwellLocationSession(
            optIn: PendingDwellCollectionOptIn(infoValue: { info[$0] }),
            access: { [self] in access },
            makeManager: { [self] in
                let manager = FakeLocationManager()
                managers.append(manager)
                return manager
            },
            diagnosticRecorder: diagnosticRecorder,
            onActivity: { [weak self] in self?.activityCount += 1 }
        )
    }
}

private final class FakeLocationManager: PendingDwellLocationManaging {
    struct Settings: Equatable {
        let accuracy: CLLocationAccuracy, distanceFilter: CLLocationDistance, pauses: Bool, background: Bool
        static let lowPowerBackground = Settings(
            accuracy: kCLLocationAccuracyThreeKilometers, distanceFilter: 3000, pauses: false, background: true
        )
    }

    var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    var distanceFilter: CLLocationDistance = kCLDistanceFilterNone
    var pausesLocationUpdatesAutomatically = true
    var allowsBackgroundLocationUpdates = false
    var onActivity: (@MainActor (PendingDwellSessionCallback) -> Void)?
    private(set) var startCalls = 0
    private(set) var stopCalls = 0
    private(set) var settingsAtStart: Settings?

    func startUpdatingLocation() {
        startCalls += 1
        settingsAtStart = Settings(
            accuracy: desiredAccuracy, distanceFilter: distanceFilter,
            pauses: pausesLocationUpdatesAutomatically, background: allowsBackgroundLocationUpdates
        )
    }

    func stopUpdatingLocation() {
        stopCalls += 1
    }
}
