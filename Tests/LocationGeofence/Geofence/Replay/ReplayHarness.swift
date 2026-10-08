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

/// The shipping SDK with only CoreLocation, the network, event delivery and the clock substituted,
/// along the line `GeofenceOSSeams.swift` draws. Don't substitute more.
@available(iOS 17.0, *)
@MainActor
final class ReplayHarness {
    // MARK: - The world

    let conditionMonitor = FakeConditionMonitor()
    let visitMonitor = ReplayVisitMonitor()
    let authority = FakeLocationAuthority()
    let api: GeofenceApiServiceMock
    private(set) var fixRequestCount = 0
    /// Read through `authority`, never directly.
    let fixes: ReplayFixProvider
    let clock: DateUtilStub
    let logger: CapturingLogger

    let gate = ReplayBoundaryGate()
    private(set) var dwellScheduler = ReplayDwellScheduler()
    private var processGeneration = UUID()
    /// Lifecycle delivery belongs to one process, even when a test retains its old graph.
    private(set) var notificationCenter = NotificationCenter()

    // MARK: - The SDK

    private(set) var monitor: CLMonitorGeofenceMonitor!
    private(set) var coordinator: GeofenceSyncCoordinatorImpl!
    private(set) var tracker: GeofenceEventTracker!
    /// Where the tracker sends; read back through `deliveredMetrics`.
    private(set) var deliveryTracker: GeofenceDeliveryTrackerMock!
    private(set) var resolver: PolygonMembershipResolver!
    /// This composition's visits. Without its own, `GeofenceBootstrap` resolves
    /// `GeofenceDwellCoordinator.shared` — a process-wide `static let` holding the storage, identity
    /// and tracker of whichever harness touched it first — and awaits it inside the process-global
    /// run chain every later drive's setup queues behind. It also leaves the resolver and
    /// coordinator on the pre-dwell paths production no longer takes.
    private(set) var dwellCoordinator: GeofenceDwellCoordinator!
    private(set) var trigger: GeofenceRefreshTrigger!

    let contextStore: BackgroundDeliveryContextStore
    let eventBus: EventBusHandlerMock

    /// Own graph: overriding `DIGraphShared.shared` would leak into suites running alongside.
    private let di = DIGraphShared()

    /// Nil, deliberately; see `feedFix`.
    private let moduleLastKnownLocation: LocationData? = nil

    var fetchQueue: [Result<GeofenceApiResponse, GeofenceApiError>] = []
    var fetchCount = 0
    var starvedFetchCount = 0

    /// Nothing answered here: the answer arrives as a later `location.fix` input.
    private(set) var acquireFixCallCount = 0

    private let storage: GeofenceStorage
    private let pendingStore: PendingGeofenceMetricStore
    private let root: URL
    /// One suite per harness. Survives `reenterProcess()`: a relaunch reads it back.
    private let defaults: UserDefaults
    private let defaultsSuite: String

    let epoch: Date

    /// Decades from now, so a record dated near today shows something read the wall clock.
    static let epochFarFromNow = Date(timeIntervalSince1970: 1000000000) // 2001-09-09

    init(epoch: Date = ReplayHarness.epochFarFromNow) {
        self.epoch = epoch
        self.root = FileManager.default.temporaryDirectory.appendingPathComponent("replay-\(UUID().uuidString)")
        self.defaultsSuite = "io.customer.replay.\(UUID().uuidString)"
        self.defaults = UserDefaults(suiteName: defaultsSuite) ?? .standard

        self.logger = CapturingLogger()
        self.clock = DateUtilStub()
        clock.givenNow = epoch

        // On the wall clock every baseline postdates its fixes and the heal refuses all.
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

        // Wired once: the recording outlives any process the drive restarts.
        authority.answerCachedLocation = { [fixes] in fixes.nextCachedLocation() }

        composeSDK()
    }

    /// Must call `onComplete`: `deliverFresh` suspends until it runs, and a multi-fence batch would
    /// silently lose all but the first.
    private static func completingDeliveryTracker() -> GeofenceDeliveryTrackerMock {
        let tracker = GeofenceDeliveryTrackerMock()
        tracker.trackMetricClosure = { _, _, onComplete in onComplete(.success(())) }
        return tracker
    }

    private func makeMonitor() -> CLMonitorGeofenceMonitor {
        let monitor = CLMonitorGeofenceMonitor(
            logger: logger,
            storage: storage,
            userDefaults: defaults,
            dateUtil: clock,
            authority: authority,
            // One for the whole drive: CoreLocation keeps monitoring while the app is dead.
            makeConditionMonitor: { [conditionMonitor] _ in conditionMonitor }
        )
        monitor.movementFixResolver.requestFreshFix = { [weak self] in self?.fixRequestCount += 1 }
        // Known limitation: the timeout always wins, so every fresh-fix request falls back to the
        // cache. Parking it on the gate instead re-parked endlessly.
        monitor.movementFixResolver.waitForTimeout = { _ in await Task.yield() }
        return monitor
    }

    private func makeRefreshTrigger() -> GeofenceRefreshTrigger {
        GeofenceRefreshTrigger(
            storage: storage,
            contextStore: contextStore,
            coordinator: { [coordinator] in coordinator },
            logger: logger,
            locationMode: .automatic,
            explicitRefreshRequested: Synchronized<Bool>(false),
            // Not the fix provider: that would read the OS cache where the drive recorded no read.
            lastKnownLocation: { [weak self] in self?.moduleLastKnownLocation },
            acquireFix: { [weak self] in self?.acquireFixCallCount += 1 }
        )
    }

    /// Rerun by `reenterProcess()`: build here only what a dying process loses.
    private func composeSDK() {
        resetProcessRuntime()
        deliveryTracker = Self.completingDeliveryTracker()
        tracker = GeofenceEventTracker(
            storage: storage,
            pendingStore: pendingStore,
            deliveryTracker: deliveryTracker,
            contextStore: contextStore,
            eventBusHandler: eventBus,
            dateUtil: clock,
            logger: logger
        )

        // Evidence and lifecycle input belong to this composition; OS conditions persist across it.
        dwellCoordinator = GeofenceDwellCoordinator(
            storage: storage,
            transitionEmitter: tracker,
            contextStore: contextStore,
            logger: logger,
            fixResolver: makeReplayFixResolver(),
            notificationCenter: notificationCenter,
            clock: DateUtilGeofenceClock(dateUtil: clock),
            waitForEvidence: { [dwellScheduler] in try await dwellScheduler.sleep(nanoseconds: $0) }
        )

        resolver = makePolygonResolver()

        monitor = makeMonitor()

        let polygonResolver: PolygonMembershipResolver = resolver
        coordinator = GeofenceSyncCoordinatorImpl(
            apiService: api,
            storage: storage,
            monitor: monitor,
            contextStore: contextStore,
            transitionEmitter: tracker,
            dwellCoordinator: dwellCoordinator,
            // The post-refresh polygon passes run here too, not on the process-wide singleton.
            polygonResolver: { polygonResolver },
            dateUtil: clock,
            logger: logger
        )

        trigger = makeRefreshTrigger()

        // Kept though `wireMonitor()` binds too: a hand-driven test never sends `module.init`.
        GeofenceMonitorBinder.bind(
            monitor: monitor,
            resolver: resolver,
            coordinator: coordinator,
            logger: logger,
            dwellCoordinator: dwellCoordinator
        )
        // Also rebinds visits to the fresh resolver on `reenterProcess()`.
        GeofenceMonitorBinder.bindVisits(
            visitMonitor: visitMonitor,
            resolver: resolver,
            contextStore: contextStore,
            dwellCoordinator: dwellCoordinator
        )

        overrideBootstrapDependencies()
    }

    private func resetProcessRuntime() {
        processGeneration = UUID()
        notificationCenter = NotificationCenter()
        dwellScheduler = ReplayDwellScheduler()
        dwellScheduler.advance(to: clock.givenNow.timeIntervalSince(epoch))
    }

    /// Everything `GeofenceBootstrap` resolves, plus `DateUtil` so a later read cannot reach the
    /// wall clock.
    private func overrideBootstrapDependencies() {
        di.override(value: logger as Logger, forType: Logger.self)
        di.override(value: clock as DateUtil, forType: DateUtil.self)
        di.override(value: storage, forType: GeofenceStorage.self)
        di.override(value: contextStore, forType: BackgroundDeliveryContextStore.self)
        di.override(value: tracker, forType: GeofenceEventTracker.self)
        // Without this, transitions land in the process-wide `PolygonMembershipResolver.shared`.
        di.override(value: resolver, forType: PolygonMembershipResolver.self)
        di.override(value: dwellCoordinator, forType: GeofenceDwellCoordinator.self)
        di.override(value: monitor as GeofenceRegionMonitoring, forType: GeofenceRegionMonitoring.self)
        di.override(value: visitMonitor as GeofenceVisitMonitoring, forType: GeofenceVisitMonitoring.self)
        di.override(value: coordinator as GeofenceSyncCoordinator, forType: GeofenceSyncCoordinator.self)
    }

    /// Call after `trigger.onModuleInit()`, as `GeofenceModuleState.setup` does.
    func wireMonitor() async {
        await GeofenceBootstrap.wireMonitor(di: di)
    }

    /// Drops what `composeSDK` builds; keeps disk stores, the condition mirror and the OS condition
    /// monitor, as a real relaunch does.
    func reenterProcess() {
        // The old consume task stays parked; the new wrapper's subscription supersedes it.
        monitor.setOnTransition(nil)
        detachFromBootstrap()
        dwellScheduler.stop()
        fixes.beginNextProcess()
        composeSDK()
    }

    /// Call before replacing a composition: the bootstrap's handlers would re-run `wireMonitor` on it.
    /// Its consume task can retain it, so remove its process-local foreground observer too.
    func detachFromBootstrap() {
        monitor.setOnReconciled(nil)
        monitor.setOnAuthorizationChanged(nil)
        if let token = monitor.foregroundObserverToken {
            NotificationCenter.default.removeObserver(token)
            monitor.foregroundObserverToken = nil
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
        UserDefaults.standard.removePersistentDomain(forName: defaultsSuite)
    }

    /// Whether the graph `GeofenceBootstrap` resolves hands out this composition's dwell
    /// coordinator rather than the process-wide `shared` one.
    var bootstrapResolvesOwnDwellCoordinator: Bool {
        di.geofenceDwellCoordinator === dwellCoordinator
    }

    /// The visit this composition's storage holds for a fence, if any.
    func storedVisit(fence: String) async -> GeofenceDwellVisit? {
        await storage.getDwellVisit(geofenceId: fence)
    }

    func hasRegisteredPolygons() async -> Bool {
        // Same filter as `evaluateAllPolygons`.
        let registered = await storage.getRegisteredBusinessIds()
        return await storage.getCachedGeofences().contains { registered.contains($0.id) && $0.vertices != nil }
    }

    /// Without the tail no line has `ev=`, and every match vacuously finds nothing. Task-local: only
    /// tasks created inside `body` inherit it.
    static func withTail<T>(_ body: () async throws -> T) async rethrows -> T {
        try await DiagnosticsGateTesting.withDiagnostics(true, body)
    }

    func loadBoundaryAnswers(fetch: [TimeInterval]) {
        gate.load(fetchAnswers: fetch)
    }

    // MARK: - Output

    var emitted: [[String: String]] { GeofenceTail.parseAll(logger.messages) }

    func emitted(ev: String) -> [[String: String]] {
        emitted.filter { $0["ev"] == ev }
    }

    /// Every row this composition's tracker sent, in order. Not carried across `reenterProcess()`.
    var deliveredMetrics: [PendingGeofenceMetric] {
        deliveryTracker.trackMetricReceivedInvocations.map(\.metric)
    }

    func resetOutput() {
        logger.reset()
    }

    /// OS answers pass through the shipping resolver's freshness filter.
    private func makeReplayFixResolver() -> MovementFixResolver {
        let generation = processGeneration
        let fixResolver = MovementFixResolver(
            logger: logger,
            dateUtil: clock,
            desiredAccuracy: kCLLocationAccuracyNearestTenMeters,
            waitForTimeout: { [dwellScheduler] seconds in
                try? await dwellScheduler.sleep(nanoseconds: UInt64(seconds * 1000000000))
            }
        )
        fixResolver.requestFreshFix = { [weak self, weak fixResolver] in
            guard let self, self.processGeneration == generation, let fixResolver else { return }
            self.fixRequestCount += 1
            if let answer = self.fixes.reserveRequestedAnswer() {
                if answer.at <= self.fixes.now {
                    fixResolver.handleDeliveredFix(answer.fix)
                } else {
                    Task { @MainActor [weak self, weak fixResolver] in
                        guard let self else { return }
                        await self.gate.park(at: answer.at, what: "requested fix") { [weak self, weak fixResolver] in
                            guard let self, self.processGeneration == generation else { return }
                            fixResolver?.handleDeliveredFix(answer.fix)
                        }
                    }
                }
            } else if self.fixes.allowsSyntheticRequestedAnswers {
                // Authored fixtures without a recorded response stream supply synthetic OS answers.
                // A refused or absent answer fails immediately; recorded runs use the real timeout.
                if let fix = self.fixes.currentPosition() {
                    fixResolver.handleDeliveredFix(fix)
                }
                fixResolver.handleRequestFailure()
            }
        }
        return fixResolver
    }

    /// The default resolver would issue a live `CLLocationManager` request from a unit test.
    private func makePolygonResolver() -> PolygonMembershipResolver {
        let fixResolver = makeReplayFixResolver()
        return PolygonMembershipResolver(
            storage: storage,
            transitionEmitter: tracker,
            logger: logger,
            contextStore: contextStore,
            dateUtil: clock,
            fixResolver: fixResolver,
            notificationCenter: notificationCenter,
            dwellCoordinator: dwellCoordinator
        )
    }
}
