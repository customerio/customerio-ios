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
/// - `CLLocationManager`, as `FakeLocationAuthority` (cached-position read, granted tier) and
///   `ReplayVisitMonitor` (visits);
/// - the geofence API, event delivery and the EventBus, so a replay never leaves the process;
/// - the clock, so a long drive replays in far less than real time.
///
/// Everything else is the shipping SDK, built the way `GeofenceBootstrap` builds it — including
/// `CLMonitorGeofenceMonitor`, which holds real policy (FIFO mutation pipeline, foreground re-arm,
/// contradiction gate, baseline heal). Substitution follows the line `GeofenceOSSeams.swift` draws.
@available(iOS 17.0, *)
@MainActor
final class ReplayHarness {
    // MARK: - The world

    /// `CLMonitor`. Holds the conditions the SDK registers and delivers the events replay pushes in.
    let conditionMonitor = FakeConditionMonitor()
    let visitMonitor = ReplayVisitMonitor()
    /// `CLLocationManager`: the granted tier, the OS radius cap, and the cached-position read.
    let authority = FakeLocationAuthority()
    let api: GeofenceApiServiceMock
    /// One-shot fix requests the SDK made through the `requestFreshFix` seams, never CoreLocation.
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
    private(set) var resolver: PolygonMembershipResolver!
    /// The real sync trigger — the rules that decide whether an input causes a sync at all.
    private(set) var trigger: GeofenceRefreshTrigger!

    let contextStore: BackgroundDeliveryContextStore
    let eventBus: EventBusHandlerMock

    /// The graph `GeofenceBootstrap` resolves from — this harness's own, never the process's.
    /// Overriding `DIGraphShared.shared` instead would leak into every suite running beside this one.
    private let di = DIGraphShared()

    /// What production's `lastKnownLocation` answers. Nil, deliberately; see `feedFix`.
    private let moduleLastKnownLocation: LocationData? = nil

    /// The drive's recorded API answers, consumed in order.
    var fetchQueue: [Result<GeofenceApiResponse, GeofenceApiError>] = []
    /// Fetches the SDK attempted, whether or not a fixture was waiting. Not `private(set)`: the
    /// fetch stub in `+Inputs` increments it.
    var fetchCount = 0
    /// Fetches with no fixture left to serve — the replay fetched more often than the drive did.
    var starvedFetchCount = 0

    /// Times the SDK asked the Location module for a fix. The answer arrives as a later
    /// `location.fix` input, so nothing is satisfied here.
    private(set) var acquireFixCallCount = 0

    private let storage: GeofenceStorage
    private let pendingStore: PendingGeofenceMetricStore
    private let root: URL
    /// The wrapper's condition mirror. One suite per harness, so drives cannot inherit each other's
    /// conditions. Survives `reenterProcess()`: it is app-container state a relaunch reads back.
    private let defaults: UserDefaults
    private let defaultsSuite: String

    /// `t0` of the scenario. Virtual time is always this plus the record's `at`.
    let epoch: Date

    /// Decades from the present on purpose: a record dated near today proves something bypassed
    /// `DateUtil` and read the wall clock.
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

        // The virtual clock, so `lastStateChangedAt` is on the drive's timeline. On the wall clock
        // every baseline postdates its fixes and the heal's `onlyIfBaselinePredates` refuses all.
        self.storage = GeofenceStorage(
            directoryURL: root.appendingPathComponent("storage"),
            dateUtil: clock
        )
        self.pendingStore = PendingGeofenceMetricStore(
            logger: logger,
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

        // Wired once: the recording is the world, so it outlives any process the drive restarts.
        authority.answerCachedLocation = { [fixes] in fixes.nextCachedLocation() }

        composeSDK()
    }

    /// Delivery is substituted, and the substitution has to **complete**.
    ///
    /// `GeofenceEventTracker.deliverFresh` suspends until `onComplete` runs. A bare mock never calls
    /// it, so `trackTransition` never returns; `transition.accepted` is logged before the send, so a
    /// single crossing looks fine while a multi-fence initial-enter batch loses all but the first.
    ///
    /// Always succeeds: `delivery.*` is note-only and never asserted.
    private static func completingDeliveryTracker() -> GeofenceDeliveryTrackerMock {
        let tracker = GeofenceDeliveryTrackerMock()
        tracker.trackMetricClosure = { _, _, onComplete in onComplete(.success(())) }
        return tracker
    }

    /// The shipping wrapper, on the OS doubles. Everything it decides runs for real.
    private func makeMonitor() -> CLMonitorGeofenceMonitor {
        let monitor = CLMonitorGeofenceMonitor(
            logger: logger,
            storage: storage,
            userDefaults: defaults,
            dateUtil: clock,
            authority: authority,
            // One condition monitor for the life of the drive: CoreLocation keeps monitoring while
            // the app is dead, which is the whole reason a crossing relaunches it.
            makeConditionMonitor: { [conditionMonitor] _ in conditionMonitor }
        )
        // Where CoreLocation would be asked for one position: counted only, never answered.
        monitor.movementFixResolver.requestFreshFix = { [weak self] in self?.fixRequestCount += 1 }
        // The real fallback is a ten-second sleep, which would land after the run (or the test)
        // ended. Substituted so it lands inside the run.
        //
        // Known limitation: `resolve()` arms this timeout before calling `requestFreshFix`, so in
        // replay the timeout always wins and every fresh-fix request falls back to the cache.
        // Parking on the gate at `now + requestTimeout` would fix it, but the same approach on the
        // recovery window re-parked endlessly and hit `fatalError`. `movement.fix.*` is note-only,
        // so a drive that reaches the fallback replays it without anything failing.
        monitor.movementFixResolver.waitForTimeout = { _ in await Task.yield() }
        return monitor
    }

    /// Builds everything on the SDK's side of the boundary. Rerun by `reenterProcess()`: what it
    /// creates is state a process loses when it dies; what it closes over survives one.
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

        // The binder routes every transition through it; without this, polygons would resolve
        // against the production singleton built from the real DI graph.
        resolver = makePolygonResolver()

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
            // The Location module's stored position, not the geofence monitor's cache read:
            // production wires this to `getLastKnownLocation()`. Answering from the fix provider
            // would make the trigger read the OS cache at a moment the drive recorded no read.
            lastKnownLocation: { [weak self] in self?.moduleLastKnownLocation },
            acquireFix: { [weak self] in self?.acquireFixCallCount += 1 }
        )

        // Kept, though `wireMonitor()` binds too: a hand-driven test never sends `module.init`,
        // and an unbound monitor would drop every crossing silently.
        GeofenceMonitorBinder.bind(
            monitor: monitor,
            resolver: resolver,
            coordinator: coordinator,
            logger: logger
        )
        // Same two reasons for visits, plus: on `reenterProcess()` this rebinds the handler to the
        // fresh resolver rather than leaving it on the outgoing one.
        GeofenceMonitorBinder.bindVisits(
            visitMonitor: visitMonitor,
            resolver: resolver,
            contextStore: contextStore
        )

        // Everything `GeofenceBootstrap` resolves, plus `DateUtil` so a later read cannot reach
        // the wall clock.
        di.override(value: logger as Logger, forType: Logger.self)
        di.override(value: clock as DateUtil, forType: DateUtil.self)
        di.override(value: storage, forType: GeofenceStorage.self)
        di.override(value: contextStore, forType: BackgroundDeliveryContextStore.self)
        di.override(value: tracker, forType: GeofenceEventTracker.self)
        // Without this, `GeofenceBootstrap` binds the process-wide `PolygonMembershipResolver.shared`
        // and every OS transition lands in another harness's storage.
        di.override(value: resolver, forType: PolygonMembershipResolver.self)
        di.override(value: monitor as GeofenceRegionMonitoring, forType: GeofenceRegionMonitoring.self)
        di.override(value: visitMonitor as GeofenceVisitMonitoring, forType: GeofenceVisitMonitoring.self)
        di.override(value: coordinator as GeofenceSyncCoordinator, forType: GeofenceSyncCoordinator.self)
    }

    /// The module's own startup, run for real — including the relaunch decision whether regions
    /// CoreLocation kept while the app was dead are adopted or registered again.
    ///
    /// Called where production calls it (`GeofenceModuleState.setup` runs `trigger.onModuleInit()`
    /// and then this), so the order of `sync.skipped`, `storage.loaded` and `registration.adopted`
    /// is the SDK's.
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
    /// condition mirror; the OS condition monitor, because CoreLocation keeps monitoring while the
    /// app is dead; the granted permission tier; the Location module's last-known position; the
    /// recording; and the log.
    ///
    /// A crossing waking a suspended app in a fresh process is the ordinary background path, so a
    /// harness that cannot replay across it cannot replay the common case.
    func reenterProcess() {
        // The old consume task stays parked on its stream; `FakeConditionMonitor` supersedes that
        // subscription when the new wrapper asks for one.
        monitor.setOnTransition(nil)
        detachFromBootstrap()
        composeSDK()
    }

    /// Stops a discarded composition from re-entering the bootstrap.
    ///
    /// Call when a harness is finished with, and before replacing its composition.
    /// `GeofenceBootstrap` installs a graph-capturing closure on the reconcile and
    /// authorization-changed handlers, and either would re-run `wireMonitor` on a dead composition.
    ///
    /// **It does not free the monitor.** The monitor's `consumeTask` holds a strong `self` for its
    /// whole loop and is never cancelled, so its `deinit` never runs and its foreground observer
    /// stays: dead monitors still react to the process-global `enterForeground()`. Each writes to
    /// its own logger and OS double, so a live drive's assertions are unaffected. Fixing it needs
    /// a cancel on the SDK side.
    func detachFromBootstrap() {
        monitor.setOnReconciled(nil)
        monitor.setOnAuthorizationChanged(nil)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
        UserDefaults.standard.removePersistentDomain(forName: defaultsSuite)
    }

    /// Whether any registered geofence is a polygon.
    ///
    /// A visit forces `evaluateAllPolygons(requiresFreshFix: true)`, and the runner refuses to
    /// grade that pass when it has polygons to judge. With none registered the pass returns before
    /// requesting a fix, so a circle-only drive's visits replay honestly.
    func hasRegisteredPolygons() async -> Bool {
        // The same filter `evaluateAllPolygons` applies: registered AND has vertices.
        let registered = await storage.getRegisteredBusinessIds()
        return await storage.getCachedGeofences().contains { registered.contains($0.id) && $0.vertices != nil }
    }

    /// Runs `body` with the diagnostic tail forced on — without it the SDK logs prose with no
    /// `ev=`, and every match vacuously finds nothing.
    ///
    /// Task-local, so concurrent suites cannot see each other's value. Only tasks created inside
    /// `body` inherit it.
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

    /// The polygon resolver, on the harness's seams.
    ///
    /// Its default `fixResolver` leaves `requestFreshFix` unset and keeps the real ten-second
    /// timeout, so a pass would issue a live `CLLocationManager` request from a unit test.
    private func makePolygonResolver() -> PolygonMembershipResolver {
        let fixResolver = MovementFixResolver(
            logger: logger,
            dateUtil: clock,
            desiredAccuracy: kCLLocationAccuracyNearestTenMeters,
            waitForTimeout: { _ in await Task.yield() }
        )
        fixResolver.requestFreshFix = { [weak self, weak fixResolver] in
            guard let self, let fixResolver else { return }
            self.fixRequestCount += 1
            // Answered the way CoreLocation would: the drive's recorded answer when the capture has
            // one, else its position now. Left only to count, every polygon in a fresh-fix pass logs
            // `no_usable_fix`. Through `handleDeliveredFix`, the delegate's entry, so a fix older
            // than `maxAge` is refused as on a device. Counterpart of Android's
            // `ReplayPolygonFreshFixSource`.
            let answer = self.fixes.requestedAnswer(within: GeofenceConstants.movementFixRequestTimeout)
            if let fix = answer ?? self.fixes.currentPosition() {
                fixResolver.handleDeliveredFix(fix)
            }
        }
        return PolygonMembershipResolver(
            storage: storage,
            transitionEmitter: tracker,
            logger: logger,
            contextStore: contextStore,
            dateUtil: clock,
            fixResolver: fixResolver
        )
    }
}
