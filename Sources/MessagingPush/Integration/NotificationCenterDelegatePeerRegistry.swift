import CioInternalCommon
import Foundation
import UserNotifications

/// Holds the external `UNUserNotificationCenterDelegate` objects ("peers") that the host app and other SDKs
/// assign to `UNUserNotificationCenter.delegate`.
///
/// The SDK installs exactly one `CioNotificationCenterDelegate` proxy as the system delegate and forwards
/// every notification callback to the peers stored here. That is what lets a delegate assigned *before*
/// `MessagingPush.initialize()` and a delegate assigned *after* it both keep receiving callbacks, instead of
/// only the most recently assigned one.
///
/// Ownership: `UNUserNotificationCenter.delegate` is a weak property, so peers are owned by the host app.
/// Implementations must hold peers weakly and must never extend a peer's lifetime. A peer the app releases
/// simply stops receiving callbacks.
///
/// Threading: `UNUserNotificationCenter.delegate` can be assigned from any thread, including reentrantly from
/// inside a callback the SDK is currently fanning out. Implementations must be safe for concurrent use, and
/// must not run peer code — or any other app-provided closure, such as a log dispatcher — while holding an
/// internal lock.
@available(iOSApplicationExtension, unavailable)
protocol NotificationDelegatePeerRegistry: AnyObject {
    /// Registers `peer` as a recipient of forwarded notification callbacks.
    ///
    /// Required semantics:
    /// - `nil` removes every registered peer. The SDK's proxy stays installed as the system delegate, so
    ///   Customer.io keeps handling pushes and no peer the app has detached is called again.
    /// - Assigning a peer that is already registered (same object identity) is a no-op: it is not stored
    ///   twice, it keeps its existing position, and it is still called exactly once per notification.
    /// - A peer that is not registered yet is appended after the already-registered peers. Sequential
    ///   assignments preserve their registration order. Assignments racing from different threads are
    ///   serialized safely, but their relative order is whichever registration acquires the lock first.
    @discardableResult
    func register(_ peer: UNUserNotificationCenterDelegate?) -> NotificationDelegateRegistrationOutcome

    /// The peers that are still alive, oldest registration first, dropping every peer that has been
    /// deallocated since the last call.
    ///
    /// The returned array holds strong references. Callers must take it once per notification delivery and use
    /// that single snapshot for the whole delivery, so the peer set cannot change part-way through a fan-out
    /// and a peer cannot be deallocated between the liveness check and the call.
    func livePeers() -> [UNUserNotificationCenterDelegate]
}

/// Describes the result of one peer-registry mutation so the top-level installer can log after releasing its
/// install lock. The registry itself never logs or calls app code.
@available(iOSApplicationExtension, unavailable)
enum NotificationDelegateRegistrationOutcome {
    case cleared(peerCount: Int)
    case alreadyRegistered
    case registered(peerCount: Int)
}

@available(iOSApplicationExtension, unavailable)
final class NotificationDelegatePeerRegistryImpl: NotificationDelegatePeerRegistry {
    /// Weak holder for one peer. The identifier is captured at registration time so that identity can be
    /// compared without resurrecting a released peer.
    private final class WeakPeerBox {
        let identifier: ObjectIdentifier
        weak var peer: UNUserNotificationCenterDelegate?

        init(peer: UNUserNotificationCenterDelegate) {
            self.identifier = ObjectIdentifier(peer)
            self.peer = peer
        }
    }

    /// Guards ``boxes``.
    ///
    /// A lock rather than an actor: both the `UNUserNotificationCenter.delegate` setter and the
    /// `UNUserNotificationCenterDelegate` callbacks are synchronous Objective-C APIs that cannot `await`, so
    /// an actor would force the SDK to answer the system asynchronously. The lock only ever guards in-memory
    /// array mutation — it is never held while peer code, app code, or a log dispatcher runs — so it cannot
    /// deadlock against a peer that reassigns `UNUserNotificationCenter.delegate` from inside a callback.
    private let lock = NSLock()
    private var boxes: [WeakPeerBox] = []

    func livePeers() -> [UNUserNotificationCenterDelegate] {
        lock.lock()
        let peers = compactAndReadLocked()
        lock.unlock()
        return peers
    }

    @discardableResult
    func register(
        _ peer: UNUserNotificationCenterDelegate?
    ) -> NotificationDelegateRegistrationOutcome {
        updateStorage(with: peer)
    }

    /// Applies the assignment to ``boxes`` and reports what happened. All mutation happens here so that the
    /// lock is confined to this function and released before anything outside the SDK is called.
    private func updateStorage(
        with peer: UNUserNotificationCenterDelegate?
    ) -> NotificationDelegateRegistrationOutcome {
        lock.lock()
        defer { lock.unlock() }

        guard let peer = peer else {
            let peerCount = compactAndReadLocked().count
            boxes = []
            return .cleared(peerCount: peerCount)
        }

        // Compact before comparing identity. A deallocated peer's `ObjectIdentifier` is just its former
        // address, which the allocator can hand to a different object, so a stale box could otherwise report
        // a false identity match against a brand new peer.
        _ = compactAndReadLocked()

        let identifier = ObjectIdentifier(peer)
        if boxes.contains(where: { $0.identifier == identifier }) {
            return .alreadyRegistered
        }

        boxes.append(WeakPeerBox(peer: peer))
        return .registered(peerCount: boxes.count)
    }

    /// Drops boxes whose peer has been deallocated and returns the surviving peers in registration order.
    /// Must be called with ``lock`` held.
    private func compactAndReadLocked() -> [UNUserNotificationCenterDelegate] {
        var survivingBoxes: [WeakPeerBox] = []
        var peers: [UNUserNotificationCenterDelegate] = []
        survivingBoxes.reserveCapacity(boxes.count)
        peers.reserveCapacity(boxes.count)

        for box in boxes {
            guard let peer = box.peer else { continue }
            survivingBoxes.append(box)
            peers.append(peer)
        }

        boxes = survivingBoxes
        return peers
    }
}

@available(iOSApplicationExtension, unavailable)
extension NotificationDelegateRegistrationOutcome {
    /// Records the result after the caller has released every install/registry lock. Logger dispatchers may
    /// execute app code, so logging deliberately does not happen as part of the registry mutation.
    func log(peer: UNUserNotificationCenterDelegate?, logger: Logger) {
        switch self {
        case .cleared(let peerCount):
            logger.debug("CIO: UNUserNotificationCenter.delegate set to nil. Cleared \(peerCount) forwarding peer(s); Customer.io's delegate stays installed.")
        case .alreadyRegistered:
            logger.debug("CIO: Notification center delegate \(String(describing: peer)) is already a forwarding peer. Keeping its existing position.")
        case .registered(let peerCount):
            logger.debug("CIO: Registered notification center delegate \(String(describing: peer)) as forwarding peer \(peerCount).")
        }
    }
}
