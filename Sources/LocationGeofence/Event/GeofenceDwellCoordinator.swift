import CioInternalCommon
import CoreLocation
import Foundation

/// Owns durable continuous visits. A deadline only requests evidence; it never proves membership.
@MainActor
final class GeofenceDwellCoordinator {
    private let transitionEmitter: GeofenceTransitionEmitting
    private var dwellEmissionsInFlight: Set<String> = []
    /// The latest EXIT each fence has seen in this process, recorded before any await. An ENTER's
    /// visit write is not ordered against a later EXIT — the two arrive on separate tasks — so a
    /// write landing after that EXIT would leave a visit open for a device already outside, and it
    /// could then qualify a dwell for a stay that had already ended. In memory only: the ENTER whose
    /// write it guards lives in the same process, and dies with it.
    private var latestExitAt: [String: Date] = [:]
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
    var foregroundObserver: NSObjectProtocol?
    var polygonVerifier: ((String) async -> Void)?

    init(
        storage: GeofenceStorage,
        transitionEmitter: GeofenceTransitionEmitting,
        contextStore: BackgroundDeliveryContextStore,
        logger: Logger,
        fixResolver: MovementFixResolver? = nil,
        notificationCenter: NotificationCenter = .default,
        freshFixProvider: (() async -> CLLocation?)? = nil,
        evidenceRetryDelay: TimeInterval = 60,
        maxEvidenceRetryAttempts: Int = 3
    ) {
        self.storage = storage
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
        if let foregroundObserver { notificationCenter.removeObserver(foregroundObserver) }
    }

    func handleBoundary(
        geofence: Geofence,
        transition: GeofenceTransition,
        occurredAt: Date,
        expectedUserId: String? = nil
    ) async {
        // Before the user check and every await: leaving is geometry, whoever is signed in, and an
        // ENTER write already in flight must see it.
        if transition == .exit { recordExit(geofenceId: geofence.id, at: occurredAt) }
        if let expectedUserId, contextStore.currentUserId != expectedUserId { return }
        switch transition {
        case .enter:
            await startVisitIfNeeded(
                geofence: geofence,
                enteredAt: occurredAt,
                expectedUserId: expectedUserId
            )
        case .exit:
            // Only the visit this EXIT read and judged: an overlapping ENTER may have written a newer
            // one since, and a delayed EXIT that found none has nothing to end.
            guard let endedVisitId = await visitEnded(
                geofence: geofence, exitedAt: occurredAt, expectedUserId: expectedUserId
            ) else { return }
            cancelEvidence(for: geofence.id, ifVisit: endedVisitId)
            await storage.removeDwellVisit(geofenceId: geofence.id, ifStill: endedVisitId)
        case .dwell:
            return
        }
    }

    /// Accept only evidence already validated against the real shape by the caller.
    /// - Parameters:
    ///   - beginsNewVisit: the evidence is an observed entry. Otherwise, with no visit stored, it
    ///     starts a candidate whose start is not reported as an entry.
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
        let stored = await currentVisit(geofence: geofence, userId: userId)
        if let continuingVisitId, stored?.visitId != continuingVisitId { return nil }
        if let stored, !beginsNewVisit || stored.enteredAt > observedAt { return stored }
        let visit = GeofenceDwellVisit(
            visitId: UUID().uuidString,
            enteredAt: observedAt,
            geometryRevision: geofence.dwellRevision,
            userId: userId,
            emitted: false,
            entryObserved: beginsNewVisit
        )
        guard await saveNewVisit(visit, geofenceId: geofence.id, replacing: stored?.visitId) else { return nil }
        scheduleDeadline(for: geofence, visit: visit)
        return visit
    }

    private func emitDwellIfQualified(
        geofence: Geofence,
        visit: GeofenceDwellVisit,
        observedAt: Date,
        source: String,
        userId: String
    ) async {
        guard geofence.dwellThresholdSeconds > 0, !visit.emitted, observedAt >= visit.enteredAt,
              Self.wholeSeconds(from: visit.enteredAt, to: observedAt) >= geofence.dwellThresholdSeconds
        else { return }
        let duration = Self.reportedSeconds(from: visit.enteredAt, to: observedAt)
        // A candidate's start is its first inside evidence, not an entry, so neither it nor the
        // time since it is reported as observed — matching Android. It still qualifies the dwell.
        let observed = visit.entryObserved
        guard contextStore.currentUserId == userId else { return }
        guard dwellEmissionsInFlight.insert(visit.visitId).inserted else { return }
        defer { dwellEmissionsInFlight.remove(visit.visitId) }
        let persisted = await transitionEmitter.trackDwell(
            geofenceId: geofence.id,
            occurredAt: observedAt,
            context: GeofenceDwellContext(
                visitId: visit.visitId,
                enteredAt: observed ? visit.enteredAt : nil,
                thresholdSeconds: geofence.dwellThresholdSeconds,
                durationSeconds: observed ? duration : nil,
                detectionSource: source
            ),
            expectedUserId: userId
        )
        guard persisted else { return }
        // The emitter suspends, so an EXIT and a re-entry may have replaced this visit meanwhile.
        // Writing the captured copy back would resurrect the old visit over the new one.
        switch await storage.markDwellVisitEmitted(visit, geofenceId: geofence.id) {
        case .marked:
            cancelEvidence(for: geofence.id)
        case .writeFailed:
            scheduleEvidenceRetry(for: geofence, visit: visit)
        case .superseded:
            // Evidence scheduling now belongs to whatever visit replaced this one.
            break
        }
    }

    private func startVisitIfNeeded(
        geofence: Geofence,
        enteredAt: Date,
        expectedUserId: String?
    ) async {
        guard tracksVisit(geofence),
              let userId = contextStore.currentUserId, !userId.isEmpty,
              expectedUserId == nil || expectedUserId == userId
        else {
            cancelEvidence(for: geofence.id)
            await storage.removeDwellVisit(geofenceId: geofence.id)
            return
        }
        let existing = await currentVisit(geofence: geofence, userId: userId)
        // A redelivered ENTER keeps the visit it belongs to. One an EXIT has already been seen
        // ending does not count: that EXIT may still be suspended before its removal, and adopting
        // the visit would leave this re-entry with none once it lands.
        if let existing, !exitOvertook(existing, geofenceId: geofence.id) {
            scheduleDeadline(for: geofence, visit: existing)
            return
        }
        let visit = GeofenceDwellVisit(
            visitId: UUID().uuidString,
            enteredAt: enteredAt,
            geometryRevision: geofence.dwellRevision,
            userId: userId,
            emitted: false
        )
        if contextStore.currentUserId == userId,
           await saveNewVisit(visit, geofenceId: geofence.id, replacing: existing?.visitId) {
            scheduleDeadline(for: geofence, visit: visit)
        }
    }

    private func recordExit(geofenceId: String, at exitedAt: Date) {
        if let recorded = latestExitAt[geofenceId], recorded >= exitedAt { return }
        latestExitAt[geofenceId] = exitedAt
    }

    /// Whether an EXIT at or after `visit` started has already been seen for the fence.
    private func exitOvertook(_ visit: GeofenceDwellVisit, geofenceId: String) -> Bool {
        guard let exitedAt = latestExitAt[geofenceId] else { return false }
        return exitedAt >= visit.enteredAt
    }

    /// Writes a new visit unless an EXIT for the fence overtook it. Checked before the write and
    /// again after it: an EXIT landing during the write may have read the store before it did, and
    /// then nothing else would close the visit. The retraction is compare-and-remove, so it cannot
    /// take out a visit written since.
    ///
    /// `replacing` is the visit the caller read, nil for none; the write is refused if an
    /// overlapping callback has stored a different one since.
    private func saveNewVisit(_ visit: GeofenceDwellVisit, geofenceId: String, replacing: String?) async -> Bool {
        guard !exitOvertook(visit, geofenceId: geofenceId),
              await storage.saveDwellVisit(visit, geofenceId: geofenceId, replacing: replacing)
        else { return false }
        guard !exitOvertook(visit, geofenceId: geofenceId) else {
            await storage.removeDwellVisit(geofenceId: geofenceId, ifStill: visit.visitId)
            return false
        }
        return true
    }

    /// The stored visit, when it still belongs to `userId` and to `geofence`'s geometry.
    /// Internal for the `+Evidence` extension.
    ///
    /// A mismatch is removed only if it is stale against the store's own cache: `geofence` can be
    /// a snapshot read before a refresh, and the visit it disagrees with may be the newer one.
    func currentVisit(
        geofence: Geofence,
        userId: String
    ) async -> GeofenceDwellVisit? {
        guard let visit = await storage.getDwellVisit(geofenceId: geofence.id) else { return nil }
        guard visit.userId == userId,
              visit.geometryRevision == geofence.dwellRevision
        else {
            await storage.removeDwellVisitIfStale(geofenceId: geofence.id, currentUserId: userId)
            return nil
        }
        return visit
    }

    /// The visit an EXIT reads and ends; nil when it found none, or found one it must leave — a
    /// visit that began after this EXIT.
    private func visitEnded(
        geofence: Geofence,
        exitedAt: Date,
        expectedUserId: String?
    ) async -> String? {
        guard let userId = contextStore.currentUserId, !userId.isEmpty,
              expectedUserId == nil || expectedUserId == userId,
              let visit = await currentVisit(geofence: geofence, userId: userId),
              // A delayed exit from an older visit must not clear a newer visit.
              exitedAt >= visit.enteredAt
        else { return nil }
        return visit.visitId
    }

    /// Whole seconds from `start` to `end`. A persisted date comes back up to one ulp (~1.2e-7 s)
    /// off — `.secondsSince1970` rounds converting out of and back into the reference epoch — so a
    /// span of exactly whole seconds can read a hair short and truncate a second low. A microsecond
    /// of slack absorbs that and rounds up no fraction anyone could observe.
    static func wholeSeconds(from start: Date, to end: Date) -> Int {
        Int((end.timeIntervalSince(start) + 0.000_001).rounded(.down))
    }

    /// The duration an event reports: the difference of the two whole epoch seconds, so it equals
    /// the event's whole-second timestamp minus the `enteredAt` it carries, which is serialized by
    /// truncation too. Can be a second more than `wholeSeconds` (100.9 s → 160.1 s reports 60, not
    /// 59); qualifying stays on `wholeSeconds`, the elapsed time actually observed.
    static func reportedSeconds(from start: Date, to end: Date) -> Int {
        max(0, Int(end.timeIntervalSince1970) - Int(start.timeIntervalSince1970))
    }

    private func tracksVisit(_ geofence: Geofence) -> Bool {
        geofence.dwellThresholdSeconds > 0
    }
}

/// Continuity across process relaunch and monitoring loss. Outside the class body only to keep
/// it under the type-length cap; same file, so `tracksVisit` stays private.
extension GeofenceDwellCoordinator {
    /// Resume persisted candidates after a process relaunch. A due deadline requests fresh
    /// evidence immediately; it does not itself prove the device remained inside.
    func resumePendingVisits(geofences: [Geofence]) async {
        guard let userId = contextStore.currentUserId, !userId.isEmpty else { return }
        for geofence in geofences where tracksVisit(geofence) {
            if let visit = await currentVisit(geofence: geofence, userId: userId) {
                scheduleDeadline(for: geofence, visit: visit)
            }
        }
    }

    /// Monitoring stopped being trustworthy, so persisted entry time can no longer support a
    /// dwell. Pending deliveries remain untouched.
    func invalidateContinuity(geofenceId: String? = nil) async {
        if let geofenceId {
            cancelEvidence(for: geofenceId)
            await storage.removeDwellVisit(geofenceId: geofenceId)
            return
        }
        deadlineTasks.values.forEach { $0.cancel() }
        deadlineTasks.removeAll()
        evidenceRetries.removeAll()
        await storage.clearDwellVisits()
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
        logger: DIGraphShared.shared.logger
    )
}
