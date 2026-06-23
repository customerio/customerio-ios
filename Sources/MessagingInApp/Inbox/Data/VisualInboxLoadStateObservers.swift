import Foundation

/// A tiny registry of live `loadState`-change observers backing
/// ``VisualInboxRepository/loadStateChanges()``.
///
/// Each observer is an `AsyncStream<Void>` continuation. The registry is a value type owned and
/// mutated exclusively from inside `VisualInboxRepositoryImpl` (an `actor`), so actor isolation
/// already serializes every `add`/`remove`/`notify` — there is no manual locking here.
///
/// Emissions are **signal-only** (carry no payload): a tick means "loadState changed, re-read the
/// current cached state". The registry never triggers a network fetch.
struct VisualInboxLoadStateObservers {
    private var observers: [UUID: AsyncStream<Void>.Continuation] = [:]

    /// Registers a continuation and immediately yields once, so a late subscriber gets the current
    /// state right away (the overlay's one-shot load may have resolved before it subscribed).
    mutating func add(id: UUID, continuation: AsyncStream<Void>.Continuation) {
        observers[id] = continuation
        continuation.yield(())
    }

    /// Drops a continuation (called on stream termination).
    mutating func remove(id: UUID) {
        observers[id] = nil
    }

    /// Fans a change signal out to every live observer.
    func notify() {
        for continuation in observers.values {
            continuation.yield(())
        }
    }
}
