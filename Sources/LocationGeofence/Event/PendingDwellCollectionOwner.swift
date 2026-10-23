import Foundation

/// The coordinator's side of the opt-in pending-dwell session: one lease per fence, for its pending
/// polygon visit, ending at a cap fixed by that visit's recording. Visits are held only to judge
/// their continuity; no fix passes through here, so nothing here is evidence.
@MainActor
final class PendingDwellCollectionOwner {
    struct Lease {
        let visit: GeofenceDwellVisit
        /// The cap, in nanoseconds of the coordinator clock's continuous uptime.
        let deadline: UInt64
    }

    private let optIn: PendingDwellCollectionOptIn
    private let makeManager: @MainActor () -> PendingDwellLocationManaging
    private let sleep: @Sendable (UInt64) async throws -> Void
    private var session: PendingDwellLocationSession?
    private var collection: PendingDwellBackgroundCollection<String>?
    /// Per fence id.
    private(set) var leases: [String: Lease] = [:]

    /// Nil unless the host opted in and a `sleep` exists: by default nothing is built and no location
    /// manager exists. `sleep` must wait on continuous time, the timeline lease caps are set on: an
    /// awake-time wait can hold the session long past them while the device sleeps. The default is nil
    /// before iOS 16, which has no continuous wait, so there the experiment stays off while geofencing
    /// and dwell run as they do without it.
    static func ifOptedIn(
        _ optIn: PendingDwellCollectionOptIn,
        makeManager: @escaping @MainActor () -> PendingDwellLocationManaging = { CoreLocationPendingDwellManager() },
        sleep: (@Sendable (UInt64) async throws -> Void)? = GeofenceContinuousWait.continuous
    ) -> PendingDwellCollectionOwner? {
        guard optIn.enabled, let sleep else { return nil }
        return PendingDwellCollectionOwner(optIn: optIn, makeManager: makeManager, sleep: sleep)
    }

    private init(
        optIn: PendingDwellCollectionOptIn,
        makeManager: @escaping @MainActor () -> PendingDwellLocationManaging,
        sleep: @escaping @Sendable (UInt64) async throws -> Void
    ) {
        self.optIn = optIn
        self.makeManager = makeManager
        self.sleep = sleep
    }

    var isRunning: Bool { session?.isRunning ?? false }

    /// Once, from the owning coordinator: the clock its visits are timed by, the access it judges
    /// them under, and the recorder its session traces to. `onActivity` must not hold the
    /// coordinator strongly.
    func bind(
        now: @escaping () -> UInt64,
        access: @escaping @MainActor () -> GeofenceLocationAccess?,
        diagnosticRecorder: DwellDiagnosticRecorder? = nil,
        onActivity: @escaping @MainActor () -> Void
    ) {
        guard session == nil else { return }
        let session = PendingDwellLocationSession(
            optIn: optIn, access: access, makeManager: makeManager,
            diagnosticRecorder: diagnosticRecorder, onActivity: onActivity
        )
        self.session = session
        collection = PendingDwellBackgroundCollection(
            now: now,
            sleep: sleep,
            start: { _ = session.start() },
            stop: { session.stop() }
        )
    }

    func set(_ lease: Lease?, geofenceId: String) {
        leases[geofenceId] = lease
    }

    /// Only `visitId`'s lease when given, so a newer visit's survives an older visit's release.
    func release(geofenceId: String, ifVisit visitId: String? = nil) {
        guard visitId == nil || leases[geofenceId]?.visit.visitId == visitId else { return }
        leases[geofenceId] = nil
    }

    /// Keeps the leases `holds` accepts, then runs the session only while one is unexpired and the
    /// access now in force allows it. Re-arms nothing.
    func reconcile(keeping holds: (String, GeofenceDwellVisit) -> Bool) {
        // A copy: `holds` may re-enter and release a lease while this iterates.
        let current = leases
        for (geofenceId, lease) in current where !holds(geofenceId, lease.visit) {
            release(geofenceId: geofenceId, ifVisit: lease.visit.visitId)
        }
        guard let collection, let session else { return }
        let byVisit = Dictionary(
            leases.values.map { ($0.visit.visitId, $0.deadline) },
            uniquingKeysWith: { Swift.min($0, $1) }
        )
        collection.update(leases: byVisit, enabled: optIn.enabled, eligible: session.isEligible)
    }
}
