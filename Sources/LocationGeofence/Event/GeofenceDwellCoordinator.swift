import CioInternalCommon
import CoreLocation
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Owns durable continuous visits. A deadline only requests evidence; it never proves membership.
///
/// Every ordering and elapsed-time decision is made on the monotonic timeline of `clock`, never on
/// wall dates alone: a wall-clock step must neither qualify a dwell early nor make a later event
/// look older than the visit it ends.
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
    /// The uptime continuity was last lost at, per fence and for every fence. Like `exitMarks`, it
    /// refuses a visit write that lands after the loss's removal ran but
    /// began before the loss. Internal for the `+Continuity` extension.
    var continuityLostUptime: [String: TimeInterval] = [:]
    var allContinuityLostUptime: TimeInterval?
    /// What EXIT durations keep between callbacks; see `GeofenceExitDurationState`. Internal for
    /// the `+ExitDuration` extension.
    var exitDuration = GeofenceExitDurationState()
    // `internal`, not `private`, only because the `+Evidence` extension file uses them.
    let storage: GeofenceStorage
    let contextStore: BackgroundDeliveryContextStore
    let fixResolver: MovementFixResolver
    let notificationCenter: NotificationCenter
    let freshFixProvider: (() async -> CLLocation?)?
    let evidenceRetryDelay: TimeInterval
    let maxEvidenceRetryAttempts: Int
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
        identityTracker: GeofenceIdentityTracker? = nil
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
        self.fixResolver = fixResolver ?? MovementFixResolver(
            logger: logger,
            backgroundTaskRunner: GeofenceBackgroundTime.runner(name: "io.customer.geofence.dwell-fix"),
            desiredAccuracy: kCLLocationAccuracyNearestTenMeters
        )
        registerForegroundEvaluation()
    }

    deinit {
        deadlineTasks.values.forEach { $0.cancel() }
        lifecycleObservers.forEach { notificationCenter.removeObserver($0) }
    }

    /// - Parameters:
    ///   - crossingObserved: whether `occurredAt` is when the boundary was crossed, not when it, or a
    ///     side, was discovered: false for a synthesized discovery, an OS correction of an assumed
    ///     state, or a heal. A discovered ENTER's visit reports no entry or duration on its dwell or
    ///     EXIT; a discovered EXIT ends its visit, untimed, as the device left at some earlier time.
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
        presenceProven: Bool = true
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
                expectedUserId: expectedUserId
            )
            // The visit ends either way; a discovered EXIT only withholds the duration it would carry.
            let context = crossingObserved ? result.context : nil
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
        continuingVisitId: String? = nil
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
        if let existing, !exitOvertook(existing, geofenceId: geofence.id),
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
            rememberIfReenteredAfterItsExit(visit, geofenceId: geofence.id)
            cancelEvidence(for: geofence.id, ifVisit: visit.visitId)
            await storage.removeDwellVisit(geofenceId: geofence.id, ifStill: visit.visitId)
            return nil
        }
        return visit
    }

    /// Whole seconds from `start` to `end`. A persisted date comes back up to one ulp (~1.2e-7 s)
    /// off — `.secondsSince1970` rounds converting out of and back into the reference epoch — so a
    /// span of exactly whole seconds can read a hair short and truncate a second low. A microsecond
    /// of slack absorbs that and rounds up no fraction anyone could observe.
    static func wholeSeconds(from start: Date, to end: Date) -> Int {
        Int((end.timeIntervalSince(start) + 0.000_001).rounded(.down))
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

extension DIGraphShared {
    @MainActor
    var geofenceDwellCoordinator: GeofenceDwellCoordinator {
        let overridden: GeofenceDwellCoordinator? = getOverriddenInstance()
        return overridden ?? GeofenceDwellCoordinator.shared
    }
}

extension GeofenceDwellCoordinator {
    @MainActor
    static let shared = GeofenceDwellCoordinator(
        storage: DIGraphShared.shared.geofenceStorage,
        transitionEmitter: DIGraphShared.shared.geofenceEventTracker,
        contextStore: DIGraphShared.shared.backgroundDeliveryContextStore,
        logger: DIGraphShared.shared.logger,
        locationAccess: { DIGraphShared.shared.geofenceMonitor.locationAccess },
        backgroundRefreshAvailable: {
            #if canImport(UIKit)
            UIApplication.shared.backgroundRefreshStatus == .available
            #else
            true
            #endif
        },
        identityTracker: DIGraphShared.shared.geofenceIdentityTracker
    )
}
