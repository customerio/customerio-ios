import Foundation

/// Collapses the completion handlers of one fan-out to N notification-delegate peers into exactly one call of
/// the system's completion handler, and merges whatever value each peer reports.
///
/// `UNUserNotificationCenterDelegate` requires the completion handler to be called exactly once. Because the
/// SDK forwards a single delivery to several peers, it has to wait for all of them and then answer the system
/// once. The aggregate guarantees exactly one outer call, whether peers complete synchronously, asynchronously,
/// out of order, more than once, or not at all because they do not implement the selector.
///
/// Usage per delivery: create one instance with the number of peers about to be invoked, invoke every peer with
/// a completion that calls ``complete(token:with:)`` using that peer's index, then call
/// ``finishDispatching()`` once the invocation loop is done.
///
/// Deliberately absent: any timeout or synthesized completion. A peer that answers `responds(to:)` with `true`
/// and then never calls its completion handler leaves the outer handler uncalled. Token arbitration could
/// ignore a reply after an SDK-selected deadline, but choosing that deadline would guess on behalf of an
/// asynchronous peer and can discard its real `willPresent` options. That policy change is outside this
/// compatibility fix. Apple may decline to present a notification when completion is not timely, so host
/// delegates must still honor the platform completion contract. A peer that retains its completion forever
/// intentionally keeps the peer snapshot and delivery object alive forever as the cost of that no-timeout policy;
/// retaining the delivery object also prevents its guarded identity from being recycled.
final class PeerDeliveryCompletionAggregate<Value> {
    /// Guards every stored property.
    ///
    /// A lock rather than an actor because the surrounding `UNUserNotificationCenterDelegate` methods are
    /// synchronous Objective-C APIs, and peers may report from any thread. It is never held while the outer
    /// completion handler — app or system code — runs.
    private let lock = NSLock()

    /// Indices of peers that have been invoked but have not reported yet.
    private var pendingTokens: Set<Int>
    /// Whether the caller has finished invoking every peer. Until then the outer handler must not fire, or a
    /// peer that completes synchronously would answer the system before its siblings were even invoked.
    private var didFinishDispatching = false
    /// The merged value so far.
    private var value: Value
    /// SDK-provided, side-effect free merge. Runs while the lock is held, so it must not call out of the SDK.
    private let merge: (Value, Value) -> Value
    /// Set to `nil` the moment it is handed out, which is what makes the outer call one-shot.
    private var onFinished: ((Value) -> Void)?
    /// The exact peer snapshot and delivery object used for this fan-out. Retaining the delivery object prevents
    /// its `ObjectIdentifier` from being recycled while the reentrancy guard still contains that identifier.
    /// These objects are released immediately after the one outer completion returns.
    private var retainedObjects: [AnyObject]
    /// Clears the proxy's reentrancy guard if every peer discards its completion closure. A peer that retains the
    /// closure for asynchronous work keeps this aggregate and its delivery object alive until it reports, including
    /// indefinitely if it never reports.
    private var onAbandoned: (() -> Void)?

    /// - Parameters:
    ///   - retainedPeers: The exact peers invoked for this delivery. `[]` is valid.
    ///   - deliveryObject: The notification or response whose identity is held by the proxy's reentrancy guard.
    ///   - initialValue: The value to return before merging peer results. The caller decides whether this is an
    ///     SDK fallback or the merge operation's identity value.
    ///   - merge: Combines the value so far with the value a peer reported. Must be order independent so the
    ///     result does not depend on which peer answers first.
    ///   - onFinished: The system's completion handler. Called exactly once, never while the lock is held.
    init(
        retaining retainedPeers: [AnyObject],
        deliveryObject: AnyObject? = nil,
        initialValue: Value,
        merge: @escaping (Value, Value) -> Value,
        onFinished: @escaping (Value) -> Void,
        onAbandoned: (() -> Void)? = nil
    ) {
        self.pendingTokens = Set(retainedPeers.indices)
        self.value = initialValue
        self.merge = merge
        self.onFinished = onFinished
        self.retainedObjects = [deliveryObject].compactMap { $0 } + retainedPeers
        self.onAbandoned = onAbandoned
    }

    deinit {
        onAbandoned?()
    }

    /// Records that the peer identified by `token` finished, merging the value it reported.
    ///
    /// Repeat calls for the same token are ignored, including the reported value: some SDKs (for example
    /// `RNFBMessagingUNUserNotificationCenter`) call a completion handler twice, and counting that twice would
    /// let one peer answer for another.
    func complete(token: Int, with value: Value) {
        lock.lock()
        guard pendingTokens.remove(token) != nil else {
            lock.unlock()
            return
        }
        self.value = merge(self.value, value)
        let finish = takeFinishHandlerIfReadyLocked()
        let mergedValue = self.value
        lock.unlock()

        if let finish = finish {
            finish(mergedValue)
            releaseRetainedObjects()
        }
    }

    /// Signals that every peer for this delivery has been invoked. Must be called exactly once, after the
    /// invocation loop. Repeat calls are ignored.
    ///
    /// This is also what completes a delivery with no peers, and what completes a delivery whose peers all
    /// answered synchronously during the loop.
    func finishDispatching() {
        lock.lock()
        guard !didFinishDispatching else {
            lock.unlock()
            return
        }
        didFinishDispatching = true
        let finish = takeFinishHandlerIfReadyLocked()
        let mergedValue = value
        lock.unlock()

        if let finish = finish {
            finish(mergedValue)
            releaseRetainedObjects()
        }
    }

    /// Hands out the outer completion handler when, and only when, every peer has been dispatched and has
    /// reported. Handing it out clears the stored reference, so no later call can fire it a second time.
    /// Must be called with ``lock`` held; the caller must invoke the returned handler after unlocking.
    private func takeFinishHandlerIfReadyLocked() -> ((Value) -> Void)? {
        guard didFinishDispatching, pendingTokens.isEmpty else { return nil }

        let handler = onFinished
        onFinished = nil
        onAbandoned = nil
        return handler
    }

    /// Releases the stable delivery snapshot. Called only by the invocation that won the one-shot finish race,
    /// and only after the outer completion returned, so a losing or reentrant call cannot release peers while
    /// the outer handler is still executing.
    private func releaseRetainedObjects() {
        lock.lock()
        let releasedObjects = retainedObjects
        retainedObjects = []
        lock.unlock()
        // Keep the snapshot alive until after unlocking so releasing a peer's final reference, and therefore
        // running arbitrary deinit code, cannot reenter this aggregate while its lock is held.
        withExtendedLifetime(releasedObjects) {}
    }
}
