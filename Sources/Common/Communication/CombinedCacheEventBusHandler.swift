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

    /// Guards `pendingRegistryWork`.
    private let registryLock = Lock.unsafeInit()

    /// Tail of the FIFO chain of observer registrations/removals.
    ///
    /// `addObserver` and `removeObserver` are synchronous entry points that must reach the
    /// `bus` actor asynchronously. Independent unstructured `Task`s carry no ordering
    /// guarantee, so `addObserver(X)` followed by `removeObserver(X)` could reach the actor
    /// in reverse order and leave a live observer behind. Chaining each operation onto the
    /// previous one restores the caller's ordering.
    private var pendingRegistryWork: Task<Void, Never>?

    public init(eventStorage: EventStorage, logger: Logger) {
        self.bus = CioEventBus()
        self.eventStorage = eventStorage
        self.logger = logger
        Task { [weak self] in
            await self?.loadEventsFromStorage()
        }
    }

    /// Appends a registry operation to the chain.
    ///
    /// `build` is handed the previously enqueued operation and must return a `Task` that
    /// awaits it before touching the bus. Reading the tail and installing the new one happen
    /// under the lock, so concurrent callers still produce a single well-defined order.
    private func chainRegistryWork(_ build: (Task<Void, Never>?) -> Task<Void, Never>) {
        registryLock.lock()
        defer { registryLock.unlock() }

        pendingRegistryWork = build(pendingRegistryWork)
    }

    /// Suspends until every registry operation enqueued before this call has been applied.
    private func awaitPendingRegistryWork() async {
        registryLock.lock()
        let pending = pendingRegistryWork
        registryLock.unlock()

        await pending?.value
    }

    /// Loads events from persistent storage into the in-memory cache on startup.
    public func loadEventsFromStorage() async {
        for eventType in EventTypesRegistry.allEventTypes() {
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
    /// Registration is applied asynchronously, but in order relative to other
    /// `addObserver`/`removeObserver` calls and to any later `postEventAndWait`.
    public func addObserver<E: EventRepresentable>(
        _ eventType: E.Type, action: @escaping (E) -> Void
    ) {
        logger.debug("CombinedCacheEventBusHandler: Adding observer for \(eventType)")
        chainRegistryWork { previous in
            Task { [weak self] in
                await previous?.value
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
                // Replay stays off the bus actor but remains ordered with other registry work.
                let eventsToReplay = registration.eventsToReplay.compactMap { $0 as? E }
                for event in eventsToReplay {
                    logger.debug("CombinedCacheEventBusHandler: Replaying event \(event)")
                    action(event)
                }

                // Deletion is idempotent and must not put file I/O on the delivery path for every
                // later registration or post.
                let storage = eventStorage
                Task {
                    for event in eventsToReplay {
                        await storage.remove(ofType: event.key, withStorageId: event.storageId)
                    }
                }
            }
        }
    }

    /// Removes all observers for `eventType`.
    ///
    /// Removal is applied asynchronously, but in order relative to other
    /// `addObserver`/`removeObserver` calls and to any later `postEventAndWait`, so an
    /// observer added and then removed never receives a subsequently posted event.
    public func removeObserver<E: EventRepresentable>(for eventType: E.Type) {
        chainRegistryWork { previous in
            Task { [weak self] in
                await previous?.value
                guard let self else { return }
                await bus.removeAllObservers(key: E.key)
            }
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
    /// Any `addObserver`/`removeObserver` requested before this call is applied first, so
    /// the observer set seen here matches what the caller last asked for.
    public func postEventAndWait<E: EventRepresentable>(_ event: E) async {
        logger.debug("CombinedCacheEventBusHandler: Posting event \(event)")
        await awaitPendingRegistryWork()
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
