@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioLocationGeofence
@testable import CioLocationGeofenceMocks
import CoreLocation
import Foundation
import SharedTests
#if canImport(UIKit)
import UIKit
#endif

/// Replay composition: the real SDK, with CoreLocation, the network and the clock replaced.
///
/// **Substituted, and nothing else:**
///
/// - `CLMonitor`, as `FakeConditionMonitor` — replay injects the events the OS delivered;
/// - `CLLocationManager`, as `FakeLocationAuthority` — it answers the cached-position read and
///   holds the granted tier the drive recorded;
/// - the geofence API, because a replay must not reach the network;
/// - the clock, because a scenario replays two hours of driving in milliseconds.
///
/// Everything above those four lines is the shipping SDK, built the way `GeofenceBootstrap` builds
/// it. That includes `CLMonitorGeofenceMonitor` itself: it is not a humble object — the FIFO
/// mutation pipeline, the foreground re-arm, the contradiction gate, the baseline-heal enqueue and
/// its candidate rule all live in it — so a harness that substituted the whole class had to
/// re-create that policy, and each re-created rule was one that could stop matching the SDK without
/// anything failing. `GeofenceOSSeams.swift` draws the line where CoreLocation actually starts, and
/// this composition substitutes only along it.
@available(iOS 17.0, *)
@MainActor
final class ReplayHarness {
    // MARK: - The world

    /// `CLMonitor`. Holds the conditions the SDK registers and delivers the events replay pushes in.
    let conditionMonitor = FakeConditionMonitor()
    /// `CLLocationManager`: the granted tier, the OS radius cap, and the cached-position read.
    let authority = FakeLocationAuthority()
    let api: GeofenceApiServiceMock
    /// One-shot fix requests the SDK made. The resolver's `requestFreshFix` seam is pointed here
    /// so a request is remembered and answered by the drive's next arriving fix, never by
    /// CoreLocation.
    private(set) var fixRequestCount = 0
    /// What the OS cache answers, per stimulus window. Read through `authority`, never directly.
    let fixes: ReplayFixProvider
    let clock: DateUtilStub
    let logger: CapturingLogger

    /// Holds the network until the drive says it answered, so an input recorded mid-sync is
    /// replayed mid-sync. See `ReplayBoundaryGate`.
    let gate = ReplayBoundaryGate()

    // MARK: - The SDK

    /// The shipping CLMonitor wrapper, on the replay seams.
    private(set) var monitor: CLMonitorGeofenceMonitor!
    private(set) var coordinator: GeofenceSyncCoordinatorImpl!
    private(set) var tracker: GeofenceEventTracker!
    /// The real sync trigger — the rules that decide whether an input causes a sync at all.
    private(set) var trigger: GeofenceRefreshTrigger!

    let contextStore: BackgroundDeliveryContextStore
    let eventBus: EventBusHandlerMock

    /// The graph `GeofenceBootstrap` resolves from — this harness's own, never the process's.
    ///
    /// `wireMonitor(di:)` takes the graph as an argument, so replay can hand it one holding these
    /// doubles instead of overriding `DIGraphShared.shared`. That distinction is the whole reason
    /// the bootstrap can run here at all: a process-global override would leak into every suite
    /// running beside this one, which is the hazard that kept the diagnostic tail off a global
    /// write in the first place.
    private let di = DIGraphShared()

    /// What production's `lastKnownLocation` answers. Nil, deliberately — a bus fix is routed to
    /// the trigger rather than cached here, so the SDK cannot be handed an anchor it never had.
    private let moduleLastKnownLocation: LocationData? = nil

    /// The drive's recorded API answers, consumed in order, as the inputs side of the harness
    /// enqueues them.
    var fetchQueue: [Result<GeofenceApiResponse, GeofenceApiError>] = []
    /// Fetches the SDK attempted, whether or not a fixture was waiting.
    private(set) var fetchCount = 0
    /// Fetches with no fixture left to serve — the replay fetched more often than the drive did.
    private(set) var starvedFetchCount = 0

    /// Set when the SDK asked the Location module for a fix. In a replay the answer arrives as the
    /// next `location.fix` input, so there is nothing to satisfy the request with here.
    private(set) var acquireFixCallCount = 0

    private let storage: GeofenceStorage
    private let pendingStore: PendingGeofenceMetricStore
    private let root: URL
    /// The wrapper's condition mirror lives here. Its own suite, so a replay never touches the
    /// machine's defaults — and one per harness, so two drives cannot inherit each other's
    /// conditions. Survives `reenterProcess()` deliberately: the mirror is app-container state, and
    /// a relaunched app reads back exactly what the dead one left.
    private let defaults: UserDefaults
    private let defaultsSuite: String

    /// `t0` of the scenario. Virtual time is always this plus the record's `at`.
    let epoch: Date

    /// The epoch is deliberately decades from the present. Every timestamp the SDK stamps should
    /// derive from it, so a record dated near *today* is proof that something bypassed `DateUtil`
    /// and read the wall clock — a difference of hours would be easy to miss, 25 years is not.
    static let epochFarFromNow = Date(timeIntervalSince1970: 1000000000) // 2001-09-09

    /// Signed out, like a freshly installed app. Identity arrives as an `identity.changed` input.
    init(epoch: Date = ReplayHarness.epochFarFromNow) {
        self.epoch = epoch
        self.root = FileManager.default.temporaryDirectory.appendingPathComponent("replay-\(UUID().uuidString)")
        self.defaultsSuite = "io.customer.replay.\(UUID().uuidString)"
        self.defaults = UserDefaults(suiteName: defaultsSuite) ?? .standard

        self.logger = CapturingLogger()
        self.clock = DateUtilStub()
        clock.givenNow = epoch

        // The virtual clock, so `lastStateChangedAt` is stamped on the drive's timeline. Against the
        // wall clock every baseline is dated decades after the fixes it is compared with, and the
        // heal's `onlyIfBaselinePredates` guard refuses every candidate.
        self.storage = GeofenceStorage(
            directoryURL: root.appendingPathComponent("storage"),
            dateUtil: clock
        )
        self.pendingStore = PendingGeofenceMetricStore(
            fileManager: .default,
            directoryURL: root.appendingPathComponent("pending")
        )
        self.contextStore = BackgroundDeliveryContextStore(
            fileManager: .default,
            directoryURL: root.appendingPathComponent("context")
        )

        self.api = GeofenceApiServiceMock()
        self.eventBus = EventBusHandlerMock()
        self.fixes = ReplayFixProvider(epoch: epoch)

        // The OS cache read, wired once: the recording is the world, so it outlives any process the
        // drive restarts. Every read goes through the real `selectFix()` from here.
        authority.answerCachedLocation = { [fixes] in fixes.nextCachedLocation() }

        composeSDK()
    }

    /// Delivery is substituted, and the substitution has to **complete**.
    ///
    /// `GeofenceEventTracker.deliverFresh` suspends on a `withCheckedContinuation` that only the
    /// `onComplete` handler resumes. A bare `GeofenceDeliveryTrackerMock` has no closure set, so
    /// that handler is never invoked, the continuation never resumes, and `trackTransition` never
    /// returns. `transition.accepted` is logged *before* the send, so one crossing still records
    /// normally and the stall stays invisible — until something awaits the call in a loop. The
    /// initial-enter batch does: it emitted the first fence of every burst and silently lost the
    /// rest, which is why `ios-iphone15-drive10-1236` was the first scenario to catch this. Every
    /// earlier iOS drive had single-fence bursts, where there is nothing behind the stall to lose.
    ///
    /// Always succeeds. `delivery.*` is note-only and never asserted, so replaying the drive's own
    /// send outcomes here would add nothing a scenario can grade.
    private static func completingDeliveryTracker() -> GeofenceDeliveryTrackerMock {
        let tracker = GeofenceDeliveryTrackerMock()
        tracker.trackMetricClosure = { _, _, onComplete in onComplete(.success(())) }
        return tracker
    }

    /// Builds everything on the SDK's side of the boundary.
    ///
    /// Split out of `init` so `reenterProcess()` can run it again. Everything it creates is state a
    /// process loses when it dies; everything it closes over — the stores, the OS doubles, the
    /// recording — is state that survives one.
    /// The shipping wrapper, on the OS doubles. Everything it decides runs for real.
    ///
    /// Its own function so `composeSDK` stays readable, and so the two seams the replay has to
    /// close are in one place rather than buried in a long constructor call.
    private func makeMonitor() -> CLMonitorGeofenceMonitor {
        let monitor = CLMonitorGeofenceMonitor(
            logger: logger,
            storage: storage,
            userDefaults: defaults,
            dateUtil: clock,
            authority: authority,
            // One condition monitor for the life of the drive: CoreLocation keeps monitoring while
            // the app is dead, which is the whole reason a crossing relaunches it.
            makeConditionMonitor: { [conditionMonitor] _ in conditionMonitor },
            // The recovery window is a real 60-second sleep by default, which a replay finishing in
            // milliseconds of wall time would never come back from inside the run.
            //
            // **Yielding is not a faithful substitute, and parking on the gate is worse.** A yield
            // costs no virtual time, so the SDK re-checks a rate limit measured on the virtual
            // clock the instant the wait returns, is refused, defers and asks again — a spin that
            // ends only when the runner next advances the clock. Parking at `now + seconds`
            // instead looks right and is not: releasing the boundary moves the clock forward by
            // the window, the SDK re-stamps `lastUnmonitoredRecoveryAt`, the next check is inside
            // the window again, and it parks again — an endless ladder that trips the gate's
            // 512-round guard and `fatalError`s the whole test process. Measured, not theorised.
            //
            // So the spin stays, as the lesser of two failures — but it is **not bounded**, and
            // nothing here can bound it. `deferUnmonitoredRecovery` re-arms from inside its own
            // `Task`, so the only exit is virtual time crossing the window; once the runner stops
            // advancing the clock after the last stimulus, the chain keeps allocating and draining
            // `Task`s on the main actor for the rest of the test *process* — `detachFromBootstrap`
            // cannot stop it, because the monitor is never freed. A crash is still worse than a
            // livelock, which is why this is the shape that ships.
            //
            // Reached by a drive with two `.unmonitored` bursts inside 60 virtual seconds. The
            // corpus has a near miss: `drive5` carries 21 `os.monitor.stopped` in two bursts, and
            // escapes only because they are ~4000 s apart. The honest fix is for the recovery to
            // be driven by the recording rather than by a wall-clock wait, which is an SDK change.
            // Tracked.
            waitForRecoveryWindow: { _ in await Task.yield() }
        )
        // Where CoreLocation would be asked for one position. The SDK's own seam for it: a request
        // is counted here and satisfied by the next recorded fix in `feedFix`.
        monitor.movementFixResolver.requestFreshFix = { [weak self] in self?.fixRequestCount += 1 }
        return monitor
    }

    private func composeSDK() {
        tracker = GeofenceEventTracker(
            storage: storage,
            pendingStore: pendingStore,
            deliveryTracker: Self.completingDeliveryTracker(),
            contextStore: contextStore,
            eventBusHandler: eventBus,
            dateUtil: clock,
            logger: logger
        )

        monitor = makeMonitor()

        coordinator = GeofenceSyncCoordinatorImpl(
            apiService: api,
            storage: storage,
            monitor: monitor,
            contextStore: contextStore,
            transitionEmitter: tracker,
            dateUtil: clock,
            logger: logger
        )

        trigger = GeofenceRefreshTrigger(
            storage: storage,
            contextStore: contextStore,
            coordinator: { [coordinator] in coordinator },
            logger: logger,
            locationMode: .automatic,
            explicitRefreshRequested: Synchronized<Bool>(false),
            // The **Location module's** stored position, not the geofence monitor's cache read.
            //
            // Production wires this to `locationServices.getLastKnownLocation()`, which returns what
            // `LocationSyncCoordinator` recorded the last time the Location module acquired a fix —
            // the same acquisitions that publish as `prov=bus`. Geofence's own resolver requests go
            // through a separate `CLLocationManager` and never reach it.
            //
            // Pointing this at the fix provider instead made the trigger pull the OS cache at a
            // moment the drive recorded no pull, which is how the stimulus-window check found it.
            lastKnownLocation: { [weak self] in self?.moduleLastKnownLocation },
            acquireFix: { [weak self] in self?.acquireFixCallCount += 1 }
        )

        // Kept, though `wireMonitor()` binds too: a hand-driven harness test never sends a
        // `module.init`, and an unbound monitor there would drop every crossing silently.
        GeofenceMonitorBinder.bind(
            monitor: monitor,
            tracker: tracker,
            coordinator: coordinator,
            logger: logger
        )

        // Everything `GeofenceBootstrap` resolves — plus `DateUtil`, which it does not read today
        // and which would answer with the wall clock if a later change made it. The
        // adopt-vs-re-register decision and the two re-run handlers are its work alone; see
        // `wireMonitor()`.
        di.override(value: logger as Logger, forType: Logger.self)
        di.override(value: clock as DateUtil, forType: DateUtil.self)
        di.override(value: storage, forType: GeofenceStorage.self)
        di.override(value: contextStore, forType: BackgroundDeliveryContextStore.self)
        di.override(value: tracker, forType: GeofenceEventTracker.self)
        di.override(value: monitor as GeofenceRegionMonitoring, forType: GeofenceRegionMonitoring.self)
        di.override(value: coordinator as GeofenceSyncCoordinator, forType: GeofenceSyncCoordinator.self)
    }

    /// The module's own startup, run for real.
    ///
    /// **This used to be one line of the harness's own** — `GeofenceMonitorBinder.bind`, in
    /// `composeSDK`. Binding is only the first of the four things `GeofenceBootstrap` does, and the
    /// one that was missing decides the most consequential question a relaunch asks: whether the
    /// regions CoreLocation kept while the app was dead are *adopted* or *registered again*. Replay
    /// silently took neither path — on the 2026-09-12 iPhone drive a re-entered process came up
    /// owning nothing, so the first sync re-added all twenty conditions where the phone re-added
    /// three, and every baseline that reseed wrote changed what the callbacks arriving in the same
    /// millisecond compared against. `storage.loaded` and `registration.adopted` are logged only
    /// here, so their absence from a replayed tail is the tell.
    ///
    /// Called where production calls it — `GeofenceModuleState.setup` runs `trigger.onModuleInit()`
    /// and then this — so the order of `sync.skipped`, `storage.loaded` and `registration.adopted`
    /// is the SDK's, not the harness's.
    func wireMonitor() async {
        await GeofenceBootstrap.wireMonitor(di: di)
    }

    /// Re-enters the process, the way the OS relaunches a suspended app to deliver a geofence event.
    ///
    /// **Dropped** — everything `composeSDK` builds: the monitor wrapper and with it the crossing
    /// pipeline's containment view, the re-add bookkeeping and the resolver's retained fix; the
    /// trigger's armed flags; the coordinator and the tracker. A real relaunch starts these empty.
    ///
    /// **Kept** — the on-disk stores (baselines, catalogue, pending deliveries, identity) and the
    /// condition mirror, because they are files and files outlive a process; the OS condition
    /// monitor, because CoreLocation goes on monitoring while the app is dead, which is the whole
    /// reason the app gets relaunched; the granted permission tier; the Location module's
    /// last-known position, which is file-backed too; the recording itself; and the log, which is
    /// the drive's record rather than anything the process owns.
    ///
    /// Needed because this is not an edge case. On the 2026-09-10 drive the second leg arrived in a
    /// fresh process on three of four handsets — a suspended app being woken by a crossing is the
    /// ordinary way background geofencing works, so a harness that cannot replay across it cannot
    /// replay the common path.
    func reenterProcess() {
        // The dead process stops listening. Its consume task is still parked on the stream it
        // subscribed to; `FakeConditionMonitor` supersedes that subscription when the new wrapper
        // asks for one, which is what a dead process looks like from the OS's side.
        monitor.setOnTransition(nil)
        // And it stops answering the bootstrap. Left attached, the outgoing monitor re-runs
        // `wireMonitor` on a reconcile or an authorization change that belongs to its successor.
        detachFromBootstrap()
        composeSDK()
    }

    /// Stops a discarded composition from re-entering the bootstrap.
    ///
    /// **Call this when a harness is finished with, and before replacing its composition.**
    /// `GeofenceBootstrap` installs one graph-capturing closure on *two* handlers — reconcile and
    /// authorization-changed — and either will re-run `wireMonitor` on a composition nobody is
    /// reading any more. Both are cleared here.
    ///
    /// **It does not free the monitor, and is not named as though it does.** The monitor's
    /// `consumeTask` captures a strong `self` and is never cancelled; it stays parked inside
    /// `for try await` for the life of the process, so every monitor the harness builds is
    /// unreachable-but-alive regardless of what the DI graph holds. Its `deinit` therefore never
    /// runs and its `willEnterForegroundNotification` observer is never removed, so dead monitors
    /// still react to `enterForeground()` — which is process-global. The harm is second-order
    /// (each writes to its own logger and its own OS double, so a live drive's assertions cannot be
    /// corrupted) but it is real, and it grows with the corpus. Fixing it needs a cancel on the
    /// SDK side; tracked separately rather than papered over here.
    func detachFromBootstrap() {
        monitor.setOnReconciled(nil)
        monitor.setOnAuthorizationChanged(nil)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
        UserDefaults.standard.removePersistentDomain(forName: defaultsSuite)
    }

    /// Runs `body` with the diagnostic tail forced on — without it the SDK logs prose with no
    /// `ev=`, and every match vacuously finds nothing.
    ///
    /// A task-local binding, so concurrent suites cannot see each other's value and this composes
    /// across the `await`s a replay is made of. It used to be a process-global write here in
    /// `init`, unsynchronized against the tail suite's lock — the one thing keeping replay off CI.
    static func withTail<T>(_ body: () async throws -> T) async rethrows -> T {
        try await DiagnosticsGateTesting.withDiagnostics(true, body)
    }

    /// Loads the moments the drive's network answered, before the first stimulus runs.
    func loadBoundaryAnswers(fetch: [TimeInterval]) {
        gate.load(fetchAnswers: fetch)
    }

    // MARK: - Output

    /// Every parseable tail the SDK emitted, in order — the matcher's input.
    var emitted: [[String: String]] { GeofenceTail.parseAll(logger.messages) }

    func emitted(ev: String) -> [[String: String]] {
        emitted.filter { $0["ev"] == ev }
    }

    func resetOutput() {
        logger.reset()
    }
}
