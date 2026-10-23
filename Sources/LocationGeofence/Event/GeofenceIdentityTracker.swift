import CioInternalCommon
import Foundation

/// The identified user and the context store's identity version and lineage, read together.
struct GeofenceIdentity: Equatable, Sendable {
    /// Nil when no user is identified.
    let userId: String?
    /// Counts every real change of user, durably: the same user on a later version was not
    /// identified throughout.
    let version: UInt64
    /// The context record the version counts in. A record lost or unreadable starts a new lineage,
    /// so a version reached again in it is not the same identity.
    let lineage: String
}

/// The identity a dwell visit is recorded under, and every change since. Its source is the context
/// store DataPipeline writes the identified user to: the store keeps a persisted identity version
/// that advances, in the same write, with every real change of user. A visit carries the version
/// it was recorded under, so a change survives the process that saw it, and any order of profile
/// events or wall-clock shifts is irrelevant: a visit is admitted only while the version it carries
/// is still the store's.
///
/// Reads the store through two internal notifications it posts and answers on
/// `NotificationCenter.default`, matched by their string values: the change notification, posted
/// synchronously as the user changes, and a snapshot request answered at subscription. Thread-safe
/// and nonisolated: the store posts on the producer's thread with its lock held, so recording here
/// reads nothing from the store and awaits nothing.
final class GeofenceIdentityTracker: @unchecked Sendable {
    /// Must match `BackgroundDeliveryContextStore`'s internal names and keys.
    static let userIdDidChangeNotification = Notification.Name("io.customer.sdk.BackgroundDeliveryContextStore.userIdDidChange")
    static let userSnapshotRequest = Notification.Name("io.customer.sdk.BackgroundDeliveryContextStore.userSnapshotRequest")
    static let userIdKey = "userId"
    static let userVersionKey = "userVersion"
    static let userLineageKey = "userLineage"
    static let replyKey = "reply"

    private let notificationCenter: NotificationCenter
    private var observer: NSObjectProtocol?
    private let current = Synchronized<GeofenceIdentity?>(nil)

    /// Observes `contextStore` from now until this tracker is released. Without a store it knows no
    /// identity, and checks nothing. `notificationCenter` must be the one the store posts on.
    init(contextStore: BackgroundDeliveryContextStore? = nil, notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
        guard let contextStore else { return }
        // Subscribed before the snapshot, so a change in between is seen by one or the other.
        self.observer = notificationCenter.addObserver(
            forName: Self.userIdDidChangeNotification, object: contextStore, queue: nil
        ) { [weak self] notification in
            guard let version = notification.userInfo?[Self.userVersionKey] as? UInt64,
                  let lineage = notification.userInfo?[Self.userLineageKey] as? String
            else { return }
            self?.record(GeofenceIdentity(
                userId: notification.userInfo?[Self.userIdKey] as? String, version: version, lineage: lineage
            ))
        }
        let reply: (String?, UInt64, String) -> Void = { [weak self] userId, version, lineage in
            self?.record(GeofenceIdentity(userId: userId, version: version, lineage: lineage))
        }
        notificationCenter.post(name: Self.userSnapshotRequest, object: contextStore, userInfo: [Self.replyKey: reply])
    }

    deinit {
        if let observer { notificationCenter.removeObserver(observer) }
    }

    /// The identity now in force; nil when this tracker observes no store.
    var currentIdentity: GeofenceIdentity? {
        current.wrappedValue
    }

    /// Whether `visit` was recorded under an identity no longer in force: another user, the same
    /// user identified again since, or a context record since lost or replaced. A visit with no
    /// version predates the field, or was recorded with no store observed; neither is judged here.
    /// One with a version but no lineage was recorded before the lineage existed, so its version
    /// cannot be told apart from a count restarted since: it is not in force.
    func interrupted(_ visit: GeofenceDwellVisit) -> Bool {
        guard let recorded = visit.identityVersion, let identity = currentIdentity else { return false }
        return recorded != identity.version || visit.identityLineage != identity.lineage || identity.userId != visit.userId
    }

    /// Within one store's lineage the version only grows, so an answer older than one already seen
    /// is dropped.
    private func record(_ identity: GeofenceIdentity) {
        current.mutating { held in
            if let held, held.lineage == identity.lineage, held.version > identity.version { return }
            held = identity
        }
    }
}

extension DIGraphShared {
    /// Nonisolated: resolved from the module's setup, off the main actor.
    var geofenceIdentityTracker: GeofenceIdentityTracker {
        let overridden: GeofenceIdentityTracker? = getOverriddenInstance()
        return overridden ?? GeofenceIdentityTracker.shared
    }
}

extension GeofenceIdentityTracker {
    /// Observes the store DataPipeline writes the identified user to.
    static let shared = GeofenceIdentityTracker(contextStore: DIGraphShared.shared.backgroundDeliveryContextStore)
}
