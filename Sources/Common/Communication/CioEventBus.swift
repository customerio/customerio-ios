import Foundation

/// Combined event bus and in-memory cache implemented as a single actor.
///
/// Merging these two responsibilities into one actor eliminates the race condition
/// in the previous design where `addObserver` and event caching were performed by
/// separate actors across two consecutive `await` points — allowing a concurrent
/// `postEventAndWait` to interleave and cause duplicate delivery.
///
/// Key invariant: `addObserver` and `post` are actor-isolated and therefore
/// cannot interleave. The snapshot returned by `addObserver` contains exactly
/// the events present at registration time; any event posted after `addObserver`
/// returns is delivered directly to the registered observer and is never in the
/// snapshot.
actor CioEventBus {
    typealias Action = (AnyEventRepresentable) -> Void

    /// Returned by `addObserver` to give the caller both a unique token (for future
    /// single-observer removal) and the cache snapshot to replay outside the actor.
    struct ObserverRegistration {
        let token: RegistrationToken
        /// Snapshot of cached events at registration time. Thread-safe to read outside
        /// the actor because Swift Array is a value type (copy-on-write).
        let eventsToReplay: [AnyEventRepresentable]
    }

    private var observers: [String: [RegistrationToken: Action]] = [:]
    private var cache: [String: RingBuffer<AnyEventRepresentable>] = [:]
    private let maxEventsPerType = 100

    /// Registers an observer and atomically snapshots the current event cache for replay.
    ///
    /// Because registration and snapshot happen inside a single actor turn, any event
    /// posted concurrently after this call returns is delivered directly to the observer
    /// and will not appear in `eventsToReplay`.
    ///
    /// The cache is intentionally **not** cleared on registration: every observer, past
    /// and future, receives the full history for its event type.
    func addObserver(key: String, action: @escaping Action) -> ObserverRegistration {
        let token = RegistrationToken()
        observers[key, default: [:]][token] = action
        return ObserverRegistration(
            token: token,
            eventsToReplay: cache[key]?.toArray() ?? []
        )
    }

    /// Removes all observers for the given key.
    func removeAllObservers(key: String) {
        observers[key] = nil
    }

    /// Removes the single observer identified by `token`, leaving other observers intact.
    func removeObserver(key: String, token: RegistrationToken) {
        observers[key]?[token] = nil
        if observers[key]?.isEmpty == true {
            observers[key] = nil
        }
    }

    /// Adds `event` to the in-memory cache and returns the current observer actions.
    ///
    /// The caller **must** invoke the returned actions outside the actor to keep
    /// delivery concurrent and avoid blocking the actor during callbacks.
    func post(_ event: AnyEventRepresentable) -> [Action] {
        let key = event.key
        cache[key, default: RingBuffer(capacity: maxEventsPerType)].enqueue(event)
        return Array((observers[key] ?? [:]).values)
    }

    /// Seeds the cache with events loaded from persistent storage on startup.
    func seedCache(_ events: [AnyEventRepresentable], forKey key: String) {
        cache[key, default: RingBuffer(capacity: maxEventsPerType)].enqueue(contentsOf: events)
    }
}
