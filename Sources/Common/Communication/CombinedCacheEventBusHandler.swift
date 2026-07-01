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

    /// Tail of the FIFO operation chain. Every bus operation started from a synchronous
    /// entry point (`addObserver`, `removeObserver`, `postEvent`) is appended here so that
    /// operations reach the actor in call order. Without this, each entry point spawning
    /// an independent `Task` allowed e.g. `addObserver` followed by `removeObserver` to be
    /// applied in reverse, leaving the observer registered.
    private let lastOperation = Synchronized<Task<Void, Never>?>(nil)

    public init(eventStorage: EventStorage, logger: Logger) {
        self.bus = CioEventBus()
        self.eventStorage = eventStorage
        self.logger = logger
        enqueue { [weak self] in
            await self?.loadEventsFromStorage()
        }
    }

    /// Appends `operation` to the FIFO chain. Each operation awaits the previous one,
    /// guaranteeing call-order execution while callers remain synchronous.
    @discardableResult
    private func enqueue(_ operation: @escaping () async -> Void) -> Task<Void, Never> {
        lastOperation.mutating { last in
            let previous = last
            let next = Task {
                await previous?.value
                await operation()
            }
            last = next
            return next
        }
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
    public func addObserver<E: EventRepresentable>(
        _ eventType: E.Type, action: @escaping (E) -> Void
    ) {
        logger.debug("CombinedCacheEventBusHandler: Adding observer for \(eventType)")
        enqueue { [weak self] in
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
            // Replay is performed outside the actor to keep delivery concurrent.
            // removeFromStorage is safe to call for events not on disk (no-op).
            for event in registration.eventsToReplay.compactMap({ $0 as? E }) {
                logger.debug("CombinedCacheEventBusHandler: Replaying event \(event)")
                action(event)
                await removeFromStorage(event)
            }
        }
    }

    /// Removes all observers for `eventType`.
    public func removeObserver<E: EventRepresentable>(for eventType: E.Type) {
        enqueue { [weak self] in
            guard let self else { return }
            await bus.removeAllObservers(key: E.key)
        }
    }

    /// Posts `event` asynchronously. Prefer `postEventAndWait` when delivery must
    /// complete before the next line of code runs (e.g. in tests).
    public func postEvent<E: EventRepresentable>(_ event: E) {
        enqueue { [weak self] in
            guard let self else { return }
            await postAndDeliver(event)
        }
    }

    /// Posts `event` and returns only after all current observers have been invoked.
    ///
    /// The event is always added to the in-memory cache. If no observers exist at
    /// post time, the event is also written to persistent storage so that a future
    /// observer can receive it via replay.
    ///
    /// Joins the FIFO operation chain, so any `addObserver`/`removeObserver` call made
    /// before this one is guaranteed to be applied before the event is delivered.
    public func postEventAndWait<E: EventRepresentable>(_ event: E) async {
        await enqueue { [weak self] in
            guard let self else { return }
            await postAndDeliver(event)
        }.value
    }

    private func postAndDeliver<E: EventRepresentable>(_ event: E) async {
        logger.debug("CombinedCacheEventBusHandler: Posting event \(event)")
        let observers = await bus.post(event)
        // Deliver outside the actor so callbacks run concurrently and cannot deadlock.
        for observer in observers {
            observer(event)
        }
        if observers.isEmpty {
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
