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
    /// still is. Learned from the persisted catalog only — at launch, on every refresh, and when a
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
    /// Reservations an admission wrote and then refused, whose retraction failed to persist, by
    /// visit id. Such a visit is judged as unreserved everywhere (`standing`) until the retraction
    /// succeeds, so the orphan is never delivered and a correction can still end the stay. In
    /// memory only: a relaunch reads the orphan as a fact. Internal for `+Emission`.
    var refusedReservations: [String: GeofenceDwellReservation] = [:]
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
    let evidenceRetryDelay: TimeInterval
    let maxEvidenceRetryAttempts: Int
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
        evidenceRetryDelay: TimeInterval = 60,
        maxEvidenceRetryAttempts: Int = 3,
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
    ///     EXIT; a discovered EXIT ends its visit and reports its duration with the whole gap since
    ///     the device was last proven inside as its uncertainty.
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
                expectedUserId: expectedUserId,
                crossingObserved: crossingObserved, insideProvenAt: insideProvenAt
            )
            let context = result.context
            // Only the visit this EXIT read and judged: an overlapping ENTER may have written a newer
            // one since, and a delayed EXIT that found none has nothing to end.
            guard let endedVisitId = result.endedVisitId else { return context }
            cancelEvidence(for: geofence.id, ifVisit: endedVisitId)
            await storage.removeDwellVisit(geofenceId: geofence.id, ifStill: endedVisitId)
            return context
        case .dwell:
            return nil
        }
    }

    /// Accept only evidence already validated against the real shape by the caller.
    /// - Parameters:
    ///   - beginsNewVisit: the evidence is an observed entry. Otherwise, with no visit stored, it
    ///     starts a candidate that supports dwell but no EXIT duration.
    ///   - continuingVisitId: evidence requested for this visit only. If that visit has ended by
    ///     the time the evidence is applied, the evidence is dropped rather than starting another.
    func recordInsideEvidence(
        geofence: Geofence,
        at observedAt: Date,
        source: String,
        expectedUserId: String? = nil,
        beginsNewVisit: Bool = false,
        continuingVisitId: String? = nil,
        qualifiesDwell: Bool = true
    ) async {
        await syncClockReference(readClock())
        guard tracksVisit(geofence),
              let userId = contextStore.currentUserId, !userId.isEmpty,
              expectedUserId == nil || expectedUserId == userId,
              let visit = await visitForEvidence(
                  geofence: geofence, observedAt: observedAt, userId: userId,
                  beginsNewVisit: beginsNewVisit, continuingVisitId: continuingVisitId
              )
        else { return }
        // The bookkeeping above still runs, so a marginal arrival starts, proves or continues its
        // visit at this time. Only a fix whose accuracy disk lies wholly inside proves the stay; a
        // reservation proven earlier still repeats its delivery.
        guard qualifiesDwell || visit.dwellReservation != nil else { return }
        await emitDwellIfQualified(
            geofence: geofence, visit: visit, observedAt: observedAt, source: source, userId: userId
        )
    }

    /// The visit inside evidence applies to: the stored one, or a new one when there is none or
    /// the evidence is an observed entry no older than it. Nil when the evidence must be dropped.
    private func visitForEvidence(
        geofence: Geofence,
        observedAt: Date,
        userId: String,
        beginsNewVisit: Bool,
        continuingVisitId: String?
    ) async -> GeofenceDwellVisit? {
        // Placed on the monotonic timeline before the first await, as it is processed.
        let observedUptime = GeofenceVisitTiming.uptime(of: observedAt, at: readClock())
        let stored = await currentVisit(geofence: geofence, userId: userId)
        if let continuingVisitId, stored?.visitId != continuingVisitId { return nil }
        // The first fresh inside proof for a candidate discovered from the anchor: the candidate
        // re-starts here, as a stay this evidence opens, so none of the time before it counts.
        if let stored, !stored.awaitsPresenceProof,
           !beginsNewVisit || (stored.timing?.entryUptime(orderedAt: readClock()) ?? .infinity) > observedUptime {
            return stored
        }
        guard let visit = makeVisit(
            geofence: geofence, enteredAt: observedAt, userId: userId,
            entryObserved: beginsNewVisit && stored?.awaitsPresenceProof != true
        ) else { return nil }
        guard await saveNewVisit(visit, geofenceId: geofence.id, replacing: stored?.visitId) else { return nil }
        scheduleDeadline(for: geofence, visit: visit)
        return visit
    }

    private func startVisitIfNeeded(
        geofence: Geofence,
        enteredAt: Date,
        expectedUserId: String?,
        entryObserved: Bool,
        presenceProven: Bool
    ) async {
        // A snapshot that tracks no visit removes none: it may predate the refresh that enabled
        // the dwell, and a fence that really stopped tracking had its visit pruned with the cache.
        guard tracksVisit(geofence),
              let userId = contextStore.currentUserId, !userId.isEmpty,
              expectedUserId == nil || expectedUserId == userId
        else { return }
        // A visit a later native ENTER supersedes is gone by now (`continuityHolds`): an ENTER that
        // is a crossing starts a stay of its own.
        let existing = await currentVisit(geofence: geofence, userId: userId)
        // A copy of the ENTER that started a visit keeps it. One an EXIT has already been seen
        // ending does not count: that EXIT may still be suspended before its removal, and adopting
        // the visit would leave this re-entry with none once it lands. Nor does a candidate awaiting
        // proof, when this ENTER is proof.
        if let existing, !exitOvertook(existing, geofenceId: geofence.id), existing.closedByObservedBoundary == nil,
           !(presenceProven && existing.awaitsPresenceProof) {
            scheduleDeadline(for: geofence, visit: existing)
            return
        }
        guard let visit = makeVisit(
            geofence: geofence, enteredAt: enteredAt, userId: userId,
            entryObserved: entryObserved, awaitsPresenceProof: !presenceProven
        ) else { return }
        if contextStore.currentUserId == userId,
           await saveNewVisit(visit, geofenceId: geofence.id, replacing: existing?.visitId) {
            if let existing { rememberVisitEndedByPendingExit(existing, geofenceId: geofence.id) }
            scheduleDeadline(for: geofence, visit: visit)
        }
    }

    /// Writes a new visit unless an EXIT or a loss of continuity for the fence overtook it. Checked
    /// before the write and again after it: an EXIT or a loss's removal landing during the write may
    /// have read the store before it did, and then nothing else would close the visit. The
    /// retraction is compare-and-remove, so it cannot take out a visit written since.
    ///
    /// `replacing` is the visit the caller read, nil for none; the write is refused if an
    /// overlapping callback has stored a different one since.
    private func saveNewVisit(_ visit: GeofenceDwellVisit, geofenceId: String, replacing: String?) async -> Bool {
        guard !isOvertaken(visit, geofenceId: geofenceId),
              await storage.saveDwellVisit(visit, geofenceId: geofenceId, replacing: replacing)
        else { return false }
        guard !isOvertaken(visit, geofenceId: geofenceId) else {
            await storage.removeDwellVisit(geofenceId: geofenceId, ifStill: visit.visitId)
            return false
        }
        return true
    }

    private func isOvertaken(_ visit: GeofenceDwellVisit, geofenceId: String) -> Bool {
        // An old ENTER dated before a backward clock step may arrive after an EXIT dated on
        // the new clock. Neither its date nor its later receipt proves re-entry. Fresh inside
        // evidence can start another candidate on the current clock instead.
        if let timing = visit.timing,
           visit.enteredAt.timeIntervalSince1970 > timing.wallOffset + timing.recordedUptime + GeofenceConstants.dwellWallClockStepTolerance,
           exitMarks[geofenceId]?.isEmpty == false {
            return true
        }
        return exitOvertook(visit, geofenceId: geofenceId) || lossOvertook(visit, geofenceId: geofenceId)
    }

    /// The stored visit, when it still belongs to `userId` and to `geofence`'s geometry, and its
    /// continuity still holds. Internal for the `+Evidence` extension.
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

    /// Internal for the `+Continuity` extension.
    func tracksVisit(_ geofence: Geofence) -> Bool {
        geofence.dwellThresholdSeconds > 0 || geofence.transitionTypes.contains(.exit)
    }
}

/// Recording new visits, outside the class body only to keep it under the type-length cap; same
/// file, so `makeVisit` stays private.
extension GeofenceDwellCoordinator {
    /// A new visit, stamped with the timeline, access and identity it is recorded under. Nil when
    /// the identity in force is no longer `userId`, which the caller read before an await.
    private func makeVisit(
        geofence: Geofence,
        enteredAt: Date,
        userId: String,
        entryObserved: Bool,
        awaitsPresenceProof: Bool = false
    ) -> GeofenceDwellVisit? {
        let identity = identityTracker.currentIdentity
        if let identity, identity.userId != userId { return nil }
        let visitId = UUID().uuidString
        visitsRecordedHere.insert(visitId)
        let reading = readClock()
        let timing = GeofenceVisitTiming(enteredAt: enteredAt, recordedAt: reading)
        return GeofenceDwellVisit(
            visitId: visitId,
            enteredAt: enteredAt,
            geometryRevision: geofence.dwellRevision,
            userId: userId,
            emitted: false,
            // An entry dated on a clock that has since stepped still starts the visit, but is not
            // reported, nor any duration from it.
            entryObserved: entryObserved && entryIsOnCurrentClock(timing, enteredAt: enteredAt, reading: reading),
            timing: timing,
            locationAccess: currentLocationAccess(),
            awaitsPresenceProof: awaitsPresenceProof,
            identityVersion: identity?.version,
            identityLineage: identity?.lineage
        )
    }
}
