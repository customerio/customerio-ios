import CioInternalCommon
import CoreLocation
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Owns durable continuous visits. A deadline only requests evidence; it never proves membership.
/// Ordering and elapsed time use `clock`'s monotonic timeline. A wall-clock step must neither qualify
/// dwell early nor make a later event look older than the visit it ends.
@MainActor
final class GeofenceDwellCoordinator {
    // `internal`, not `private`, only because the `+Emission` extension file uses them.
    let transitionEmitter: GeofenceTransitionEmitting
    var dwellEmissionsInFlight: Set<String> = []
    /// The EXITs each fence has seen in this process, recorded before any await. An ENTER's visit
    /// write is not ordered against a later EXIT — the two arrive on separate tasks — so a write
    /// landing after that EXIT would leave a visit open for a device already outside, and it could
    /// then qualify a dwell for a stay that had already ended. In memory only: the ENTER whose write
    /// it guards lives in the same process, and dies with it. Internal for `+Chronology`.
    var exitMarks: [String: [GeofenceExitMark]] = [:]
    /// The latest native ENTERs each fence has seen in this process, a crossing and a correction,
    /// noted as the OS delivers them, before the callback re-arms any evidence. A visit one ends is
    /// not the stay it reports. Internal for `+Chronology`.
    var enterMarks: [String: GeofenceEnterMarks] = [:]
    /// Fences known to be polygons. The OS monitors only a polygon's covering circle: a correction
    /// of the state it assumed for that circle proves nothing about the polygon and is never noted
    /// as a mark, so it can neither end nor restart the polygon's visit; a crossing of the circle
    /// is held until the polygon's own evidence judges it (`heldCoveringCrossings`). Learned from the persisted catalog only — at launch, on every refresh, and when a
    /// covering-circle ENTER is routed (`forgetCoveringCircleEnter`, which reads the shape from
    /// storage, so a cold wake before the load is corrected there) — never from a fence a caller
    /// holds, which may predate a refresh. Internal for `+Chronology`.
    var polygonIds: Set<String> = []
    /// Bumped whenever a refresh replaces the catalog (`rememberCatalog`), so a catalog read begun
    /// before it cannot re-add a polygon the refresh dropped. Internal for `+Polygons`.
    var polygonCatalogGeneration: UInt64 = 0
    /// Whether `polygonIds` has been read from the catalog at least once. Until then a correction
    /// cannot be told apart from a covering circle's, so it waits in `pendingCorrections` and is
    /// noted at the load, for circles only. Internal for `+Chronology` and `+Polygons`.
    var polygonIdsLoaded = false
    var pendingCorrections: [(geofenceId: String, mark: GeofenceExitMark)] = []
    /// Set between `beginCatalogReplacement` and `rememberCatalog`: a shape read begun now would
    /// read whichever catalog the write has reached, so it waits in `pendingShapeChecks` instead.
    var catalogReplacementInProgress = false
    var pendingShapeChecks: [String] = []
    /// A polygon's covering-circle crossings, from the callback until the routed ENTER reads the
    /// polygon's own evidence (`judgeCoveringCrossing`): the OS often reports the circle late, for
    /// an arrival a fix already began the visit with. Each refuses a first DWELL meanwhile, as a
    /// noted crossing would, but ends no visit. Internal for `+Chronology` and `+Polygons`.
    var heldCoveringCrossings: [String: GeofenceExitMark] = [:]
    /// Crossings seen before the shapes were loaded, by fence, held unnoted until the load tells a
    /// circle's (noted then) from a polygon's covering circle's (held for its routed ENTER, in
    /// `heldCoveringCrossings`). Each refuses a first DWELL meanwhile but ends no visit, so a read
    /// before the load cannot end a polygon's stay on its covering circle. Internal for the same.
    var unjudgedCrossings: [String: GeofenceExitMark] = [:]
    /// Whether the OS monitor dates its events at receipt rather than by the event itself
    /// (`GeofenceRegionMonitoring.datesEventsAtReceipt`); set by the binder. A circle EXIT dated at
    /// receipt bounds its departure only by the whole stay. Internal for `+ExitDuration`.
    var osExitDatesAreReceipts = false
    var pendingExitCallbacks: [String: [Date: GeofencePendingExitCallback]] = [:] // `noteExitCallback`
    /// This coordinator's first clock reading, taken when it was built; the wall offset of its
    /// previous reading, and the uptime it last saw the wall clock step at. Internal for
    /// `+Chronology`.
    let firstReading: GeofenceClockReading
    var lastWallOffset: TimeInterval?
    var wallStepSeenUptime: TimeInterval?
    /// The clock reference an earlier process persisted, loaded once; and the one this process
    /// last persisted. Internal for `+Chronology`.
    var clockReferenceLoad: Task<GeofenceClockReading?, Never>?
    var clockReferenceAtLaunch: GeofenceClockReading?
    var persistedClockReference: GeofenceClockReading?
    /// The uptime continuity was last lost at, per fence and for every fence. Like `exitMarks`, it refuses
    /// a visit write that lands after the loss's removal ran but began before the loss. Internal for `+Continuity`.
    var continuityLostUptime: [String: TimeInterval] = [:]
    var allContinuityLostUptime: TimeInterval?
    /// EXIT duration state between callbacks; see `GeofenceExitDurationState` and `+ExitDuration`.
    var exitDuration = GeofenceExitDurationState()
    // `internal`, not `private`, only because the `+Evidence` extension file uses them.
    let storage: GeofenceStorage
    let contextStore: BackgroundDeliveryContextStore
    let fixResolver: MovementFixResolver
    let notificationCenter: NotificationCenter
    let freshFixProvider: (() async -> CLLocation?)?
    /// The wait before an ordinary retry of a dwell-proof request.
    let evidenceRetryDelay: TimeInterval
    /// The least uptime between two dwell-proof requests issued for one visit, short retry aside
    /// (`admitDwellProofRequest`): `evidenceRetryDelay` unless a test drives requests itself.
    let dwellProofSpacing: TimeInterval
    /// Retries after a visit's first dwell-proof request; with that one, its whole budget
    /// (`dwellProofBudget`).
    let maxEvidenceRetryAttempts: Int
    let logger: Logger
    /// Visits whose spent budget this process has logged, so it is logged once.
    var exhaustedProofBudgetsLogged: Set<String> = []
    /// What each visit has spent proving its dwell, by visit id: authoritative in this process,
    /// merged with what was persisted, so admission reads it without awaiting storage.
    var proofLedgers: [String: GeofenceDwellProofLedger] = [:]
    /// Visits whose last admitted dwell-proof request is counted in memory but not yet confirmed
    /// saved. None of them is admitted another until it is, so a process dying loses at most one.
    var unsavedProofCharges: Set<String> = []
    /// Visits whose ledger changed since it was last saved (`persistProofLedger`).
    var dirtyProofLedgers: Set<String> = []
    /// Waits out an evidence deadline or retry. Deadlines are computed on `clock`, continuous uptime in
    /// production, so the default waits on continuous time where the OS has it; before iOS 16 it keeps
    /// `Task.sleep(nanoseconds:)`, which may end late across device sleep. Either way it only resumes a
    /// task, which runs while the app does: it is not an OS execution deadline.
    let waitForEvidence: @MainActor (UInt64) async throws -> Void
    /// The pending evidence request per geofence: the deadline, or a bounded retry after it.
    var deadlineTasks: [String: Task<Void, Never>] = [:]
    var evidenceRetries: [String: EvidenceRetryState] = [:]
    var lifecycleObservers: [NSObjectProtocol] = []
    /// Visits this instance recorded: a process's own. Internal for the `+Continuity` extension.
    var visitsRecordedHere: Set<String> = []
    /// The uptime the app last moved between foreground and background. A visit recorded under
    /// access that observes nothing in the background cannot span it. Internal for `+Continuity`.
    var foregroundOnlyLostUptime: TimeInterval?
    var polygonVerifier: ((String) async -> Void)?
    /// Test seam, nil in production: told true as a deadline or retry starts its evidence check and
    /// false as it ends, so a test driving virtual time can wait for the checks it released.
    var evidenceCheckActivity: (@MainActor (Bool) -> Void)?
    /// The opt-in pending-dwell session; nil unless the host opted in. See `+Collection`.
    let pendingDwellCollection: PendingDwellCollectionOwner?
    /// Opt-in dwell diagnostics, shared with the default fix resolver; nil records nothing.
    let diagnosticRecorder: DwellDiagnosticRecorder?
    /// Every visit timing decision reads this clock.
    let clock: GeofenceClock
    /// The location access now in force; nil when unknown, which never invalidates a visit.
    let locationAccess: (@MainActor () -> GeofenceLocationAccess?)?
    /// Whether Background App Refresh is available to the app; nil when unknown, taken as available.
    let backgroundRefreshAvailable: (@MainActor () -> Bool)?
    var lastBackgroundRefreshAvailable: Bool?
    /// Identities the profile callback has reported, kept off the main actor.
    let identityTracker: GeofenceIdentityTracker

    init(
        storage: GeofenceStorage,
        transitionEmitter: GeofenceTransitionEmitting,
        contextStore: BackgroundDeliveryContextStore,
        logger: Logger,
        fixResolver: MovementFixResolver? = nil,
        notificationCenter: NotificationCenter = .default,
        freshFixProvider: (() async -> CLLocation?)? = nil,
        evidenceRetryDelay: TimeInterval = 120,
        maxEvidenceRetryAttempts: Int = 3,
        dwellProofSpacing: TimeInterval? = nil,
        clock: GeofenceClock = SystemGeofenceClock(),
        locationAccess: (@MainActor () -> GeofenceLocationAccess?)? = nil,
        backgroundRefreshAvailable: (@MainActor () -> Bool)? = nil,
        identityTracker: GeofenceIdentityTracker? = nil,
        pendingDwellCollection: PendingDwellCollectionOwner? = nil,
        diagnosticRecorder: DwellDiagnosticRecorder? = nil,
        waitForEvidence: @escaping @MainActor (UInt64) async throws -> Void = {
            try await GeofenceContinuousWait.preferringContinuous(nanoseconds: $0)
        }
    ) {
        self.identityTracker = identityTracker ?? GeofenceIdentityTracker()
        self.storage = storage
        self.clock = clock
        self.firstReading = clock.read()
        self.locationAccess = locationAccess
        self.backgroundRefreshAvailable = backgroundRefreshAvailable
        self.lastBackgroundRefreshAvailable = backgroundRefreshAvailable?()
        self.transitionEmitter = transitionEmitter
        self.contextStore = contextStore
        self.notificationCenter = notificationCenter
        self.freshFixProvider = freshFixProvider
        self.evidenceRetryDelay = evidenceRetryDelay
        self.dwellProofSpacing = max(0, dwellProofSpacing ?? evidenceRetryDelay)
        self.logger = logger
        self.maxEvidenceRetryAttempts = max(0, maxEvidenceRetryAttempts)
        self.waitForEvidence = waitForEvidence
        self.pendingDwellCollection = pendingDwellCollection
        self.diagnosticRecorder = diagnosticRecorder
        self.fixResolver = fixResolver ?? MovementFixResolver(
            logger: logger,
            backgroundTaskRunner: GeofenceBackgroundTime.runner(name: "io.customer.geofence.dwell-fix"),
            desiredAccuracy: kCLLocationAccuracyNearestTenMeters,
            diagnosticRecorder: diagnosticRecorder
        )
        // The recorder judges identity itself, so a change another writer already synced is not cleared again.
        diagnosticRecorder?.syncIdentity()
        registerForegroundEvaluation()
        bindPendingDwellCollection()
        loadPolygonIds()
    }

    deinit {
        deadlineTasks.values.forEach { $0.cancel() }
        lifecycleObservers.forEach { notificationCenter.removeObserver($0) }
    }

    /// - Parameters:
    ///   - crossingObserved: whether `occurredAt` is when the boundary was crossed, not when it, or a
    ///     side, was discovered: false for a synthesized discovery, an OS correction of an assumed
    ///     state, or a heal. A discovered ENTER's visit reports no entry or duration on its dwell or
    ///     EXIT. Any EXIT, discovered or OS-decided, reports its duration with the gap since the
    ///     device was last proven inside as its uncertainty.
    ///   - insideProvenAt: for a polygon EXIT, when the device was last decisively proven inside.
    ///     It bounds the EXIT's uncertainty; nil falls back to the entry.
    ///   - presenceProven: for an ENTER, whether anything showed the device there: false only for
    ///     an ENTER synthesized from the refresh anchor, a location nothing proved current. The
    ///     candidate it starts counts no time until a fresh fix proves it.
    @discardableResult
    func handleBoundary(
        geofence: Geofence,
        transition: GeofenceTransition,
        occurredAt: Date,
        expectedUserId: String? = nil,
        detectionSource: String? = nil,
        crossingObserved: Bool = true,
        presenceProven: Bool = true,
        insideProvenAt: Date? = nil
    ) async -> GeofenceExitContext? {
        // Placed on the monotonic timeline as it is processed, before any await.
        let reading = readClock()
        let source: GeofenceExitMark.Source = transition == .enter ? .enterEvent : .exitEvent
        let mark = GeofenceExitMark(date: occurredAt, processedAt: reading, source: source)
        // Before the user check and every await: leaving is geometry, whoever is signed in, and an
        // ENTER write already in flight must see it.
        if transition == .exit { recordExitEvent(mark, geofenceId: geofence.id) }
        defer { if transition == .exit { exitRoutingEnded(at: mark.date, geofenceId: geofence.id) } }
        if transition == .enter, presenceProven { noteEnter(mark, geofenceId: geofence.id, crossing: crossingObserved) }
        if let expectedUserId, contextStore.currentUserId != expectedUserId { return nil }
        await syncClockReference(reading)
        switch transition {
        case .enter:
            await startVisitIfNeeded(
                geofence: geofence,
                enteredAt: occurredAt,
                expectedUserId: expectedUserId,
                entryObserved: crossingObserved,
                presenceProven: presenceProven
            )
            return nil
        case .exit:
            let result = await exitContext(
                geofence: geofence,
                exit: mark, processedAt: reading,
                detectionSource: detectionSource ?? (geofence.vertices == nil ? "native" : "location_evidence"),
                expectedUserId: expectedUserId, insideProvenAt: insideProvenAt
            )
            let context = result.context
            // Only the visit this EXIT read and judged: an overlapping ENTER may have written a newer
            // one since, and a delayed EXIT that found none has nothing to end.
            guard let endedVisitId = result.endedVisitId else { return context }
            cancelEvidence(for: geofence.id, ifVisit: endedVisitId)
            // A DWELL the stay qualified but never got into the outbox goes first; if it still
            // cannot, the removal keeps it as an orphan for the launch sweep.
            await flushOwedDwell(geofence: geofence, visitId: endedVisitId, exitedAt: mark.date)
            await storage.removeDwellVisit(geofenceId: geofence.id, ifStill: endedVisitId, endedAt: mark.date)
            return context
        case .dwell:
            return nil
        }
    }

    /// The stored visit, when it still belongs to `userId` and to `geofence`'s geometry, and its
    /// continuity still holds. Internal for the `+Evidence` and `+VisitRecording` extensions.
    ///
    /// A mismatch is removed only if it is stale against the store's own cache: `geofence` can be
    /// a snapshot read before a refresh, and the visit it disagrees with may be the newer one. A
    /// visit whose continuity broke is removed compare-and-remove, so a newer one survives.
    func currentVisit(
        geofence: Geofence,
        userId: String
    ) async -> GeofenceDwellVisit? {
        guard let visit = await storage.getDwellVisit(geofenceId: geofence.id),
              contextStore.currentUserId == userId
        else { return nil }
        guard visit.userId == userId,
              visit.geometryRevision == geofence.dwellRevision
        else {
            await storage.removeDwellVisitIfStale(geofenceId: geofence.id, currentUserId: userId, ifStill: visit.visitId)
            return nil
        }
        guard continuityHolds(for: visit, geofenceId: geofence.id) else {
            rememberIfReenteredAfterItsExit(visit, geofenceId: geofence.id, isCircle: geofence.vertices == nil)
            cancelEvidence(for: geofence.id, ifVisit: visit.visitId)
            await storage.removeDwellVisit(geofenceId: geofence.id, ifStill: visit.visitId)
            return nil
        }
        return visit
    }

    /// Internal for the `+Continuity` and `+VisitRecording` extensions.
    func tracksVisit(_ geofence: Geofence) -> Bool {
        geofence.dwellThresholdSeconds > 0 || geofence.transitionTypes.contains(.exit)
    }
}
