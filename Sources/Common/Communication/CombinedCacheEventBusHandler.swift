import Foundation

// sourcery: InjectRegisterShared = "EventBusHandler"
// sourcery: InjectSingleton
/// Actor-backed implementation of `EventBusHandler`.
///
/// Uses a single `CioEventBus` actor that serializes observer registration and event
/// enqueuing atomically, eliminating the race condition where an event could be both
/// directly delivered and replayed.
public class CombinedCacheEventBusHandler: EventBusHandler {
    private let bus: CioEventBus
    let eventStorage: EventStorage
    let logger: Logger

    /// Tails of the FIFO chains of observer registrations/removals, grouped by event key.
    ///
    /// `addObserver` and `removeObserver` are synchronous entry points that must reach the
    /// `bus` actor asynchronously. Independent unstructured `Task`s carry no ordering
    /// guarantee, so `addObserver(X)` followed by `removeObserver(X)` could reach the actor
    /// in reverse order and leave a live observer behind. Chaining operations for the same
    /// event key restores the caller's ordering without chaining unrelated event types together.
    /// Startup loads still share one `EventStorage` actor, so their disk reads are serialized.
    ///
    /// The dictionary retains only the latest tail encountered for each event key. SDK event
    /// types are finite, so pruning completed tails would add race-prone bookkeeping for no
    /// meaningful memory benefit.
    private let pendingRegistryWork = Synchronized<[String: Task<Void, Never>]>([:])

    /// Tails of best-effort persistent cleanup work, grouped by event key.
    ///
    /// Cleanup is retained and serialized separately from registry work so disk operations
    /// do not delay observer registration or replay delivery. Cleanup can still contend with
    /// later persistence work performed by the same `EventStorage` actor.
    private let pendingCleanupWork = Synchronized<[String: Task<Void, Never>]>([:])

    public init(eventStorage: EventStorage, logger: Logger) {
        self.bus = CioEventBus()
        self.eventStorage = eventStorage
        self.logger = logger

        // Seed each event cache on the same per-key chain used by observer registration.
        // This makes startup ordering deterministic without blocking unrelated event types.
        for eventType in EventTypesRegistry.allEventTypes() {
            enqueueStoredEventsLoad(for: eventType)
        }
    }

    deinit {
        pendingRegistryWork.using { $0.values.forEach { $0.cancel() } }
    }

    /// Appends a registry operation to the chain for `key`.
    ///
    /// Reading the previous tail and installing the new one happen in one synchronized
    /// mutation, so concurrent callers still produce a single well-defined order per key.
    /// This is internal only as a deterministic concurrency-test seam; production callers
    /// should use the public observer APIs.
    @discardableResult
    func chainRegistryWork(forKey key: String, operation: @escaping () async -> Void) -> Task<Void, Never> {
        pendingRegistryWork.mutating { workByKey in
            let previous = workByKey[key]
            let next = Task {
                await previous?.value
                guard !Task.isCancelled else { return }
                await operation()
            }
            workByKey[key] = next
            return next
        }
    }

    /// Suspends until registry work previously enqueued for `key` has been applied.
    private func awaitPendingRegistryWork(forKey key: String) async {
        let pending = pendingRegistryWork.using { $0[key] }
        await pending?.value
    }

    /// Schedules idempotent storage cleanup without adding file I/O to the delivery path.
    private func enqueueCleanup<E: EventRepresentable>(for events: [E], key: String) {
        guard !events.isEmpty else { return }

        let storage = eventStorage
        pendingCleanupWork.mutating { workByKey in
            let previous = workByKey[key]
            workByKey[key] = Task {
                await previous?.value
                for event in events {
                    await storage.remove(
                        ofType: event.key,
                        withStorageId: event.storageId
                    )
                }
            }
        }
    }

    /// Loads events from persistent storage into the in-memory cache on startup.
    public func loadEventsFromStorage() async {
        let loadTasks = EventTypesRegistry.allEventTypes().map { eventType in
            enqueueStoredEventsLoad(for: eventType)
        }
        for loadTask in loadTasks {
            await loadTask.value
        }
    }

    @discardableResult
    private func enqueueStoredEventsLoad(
        for eventType: any EventRepresentable.Type
    ) -> Task<Void, Never> {
        chainRegistryWork(forKey: eventType.key) { [weak self] in
            guard let self else { return }
            do {
                let events: [AnyEventRepresentable] = try await eventStorage.loadEvents(
                    ofType: eventType.key
                )
                await bus.seedCache(events, forKey: eventType.key)
            } catch {
                logger.debug(
                    "CombinedCacheEventBusHandler: Error loading events for \(eventType): \(error)"
                )
            }
        }
    }

    /// Registers an observer for `eventType` and replays cached history to it.
    ///
    /// Registration and the cache snapshot are taken atomically inside the actor.
    /// Events posted after registration returns are delivered directly to the observer;
    /// events already in the cache at registration time are replayed exactly once.
    ///
    /// Registration is applied asynchronously, but in order relative to other registry
    /// calls and to any later `postEventAndWait` for the same event key.
    public func addObserver<E: EventRepresentable>(
        _ eventType: E.Type, action: @escaping (E) -> Void
    ) {
        logger.debug("CombinedCacheEventBusHandler: Adding observer for \(eventType)")
        chainRegistryWork(forKey: E.key) { [weak self] in
            guard let self else { return }
            let registration = await bus.addObserver(key: E.key) { [weak self] event in
                guard self != nil else { return }
                if let typed = event as? E {
                    action(typed)
                } else {
                    self?.logger.debug(
                        "CombinedCacheEventBusHandler: Event type mismatch for key \(E.key)"
                    )
                }
            }
            // Replay stays off the bus actor but remains ordered with registry work and
            // awaited posts for this key. Observer actions are synchronous; they must not
            // block while waiting for work that is itself queued behind this chain.
            let eventsToReplay = registration.eventsToReplay.compactMap { $0 as? E }
            for event in eventsToReplay {
                logger.debug("CombinedCacheEventBusHandler: Replaying event \(event)")
                action(event)
            }
            // Removal is idempotent and runs on a separately retained chain so slow file I/O
            // never stalls replay delivery or registry ordering. A process terminated before
            // cleanup finishes can replay the event again on its next launch.
            enqueueCleanup(for: eventsToReplay, key: E.key)
        }
    }

    /// Removes all observers for `eventType`.
    ///
    /// Removal is applied asynchronously, but in order relative to other registry calls and
    /// to any later `postEventAndWait` for the same event key, so an observer added and then
    /// removed never receives a subsequently posted event of that type.
    public func removeObserver<E: EventRepresentable>(for eventType: E.Type) {
        chainRegistryWork(forKey: E.key) { [weak self] in
            guard let self else { return }
            await bus.removeAllObservers(key: E.key)
        }
    }

    /// Posts `event` asynchronously. This fire-and-forget API does not guarantee ordering
    /// relative to later calls; use `postEventAndWait` when delivery or ordering matters.
    public func postEvent<E: EventRepresentable>(_ event: E) {
        Task { [weak self] in
            guard let self else { return }
            await postEventAndWait(event)
        }
    }

    /// Posts `event` and returns only after all current observers have been invoked.
    ///
    /// The event is always added to the in-memory cache. If no observers exist at
    /// post time, a persistent event is also written to storage so a future observer
    /// can receive it via replay. Transient events (`isPersistent == false`) are never
    /// written to disk — they are only useful in the moment.
    ///
    /// Any `addObserver`/`removeObserver` requested before this call for the same event key
    /// is applied first, so the observer set seen here matches what the caller last asked for.
    public func postEventAndWait<E: EventRepresentable>(_ event: E) async {
        logger.debug("CombinedCacheEventBusHandler: Posting event \(event)")
        await awaitPendingRegistryWork(forKey: event.key)
        let observers = await bus.post(event)
        // Deliver outside the actor so callbacks run concurrently and cannot deadlock.
        for observer in observers {
            observer(event)
        }
        if observers.isEmpty, event.isPersistent {
            logger.debug("CombinedCacheEventBusHandler: No observers, persisting event \(event)")
            do {
                try await eventStorage.store(event: event)
            } catch {
                logger.debug("CombinedCacheEventBusHandler: Error storing event: \(error)")
            }
        }
    }

    /// Removes `event` from persistent storage. Safe to call for events not on disk.
    public func removeFromStorage<E: EventRepresentable>(_ event: E) async {
        await eventStorage.remove(ofType: event.key, withStorageId: event.storageId)
    }
}
