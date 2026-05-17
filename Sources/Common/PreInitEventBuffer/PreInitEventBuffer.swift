import Foundation

/// A bounded FIFO buffer that absorbs event-shaped public-API calls invoked
/// before the SDK has been initialized.
///
/// While in the `buffering` state, calls are stored as closures. Once a real
/// `CustomerIOInstance` is available, `transitionToReady(_:)` synchronously
/// replays the buffered calls in order against it; subsequent enqueues execute
/// immediately.
///
/// Capacity defaults to 100 events. When the buffer is full, **the most recent
/// enqueue is dropped** (the oldest events are preserved) — favouring
/// install-attribution and the first `identify` call, which tend to be the
/// highest-value early events. This is a deliberate divergence from the
/// rewrite (which drops oldest); see the porting plan.
///
/// Thread safety: state transitions are protected by `Synchronized<State>`.
/// Block execution happens outside the lock to avoid re-entrancy.
final class PreInitEventBuffer {
    typealias Block = (CustomerIOInstance) -> Void

    private enum State {
        case buffering([Block])
        case draining(CustomerIOInstance, [Block])
        case ready(CustomerIOInstance)
    }

    private enum EnqueueOutcome {
        case enqueued(bufferedCount: Int)
        case dropped
        case executeNow(CustomerIOInstance)
    }

    private let state: Synchronized<State>
    private let droppedCount = Synchronized<Int>(0)
    private let capacity: Int
    private let loggerProvider: () -> Logger?

    init(
        capacity: Int = 100,
        loggerProvider: @escaping () -> Logger? = { DIGraphShared.shared.logger }
    ) {
        self.capacity = capacity
        self.loggerProvider = loggerProvider
        self.state = Synchronized<State>(.buffering([]))
    }

    /// Enqueue a call for future replay, or execute it immediately if the buffer
    /// is already in the `ready` state. If the buffer is at capacity, the new
    /// call is dropped and the running drop counter is incremented (logged on
    /// the next `transitionToReady`).
    func enqueue(_ block: @escaping Block) {
        let outcome: EnqueueOutcome = state.mutating { state -> EnqueueOutcome in
            switch state {
            case .buffering(let blocks):
                if blocks.count >= self.capacity {
                    return .dropped
                }
                let newBlocks = blocks + [block]
                state = .buffering(newBlocks)
                return .enqueued(bufferedCount: newBlocks.count)
            case .draining(let impl, let pending):
                let newPending = pending + [block]
                state = .draining(impl, newPending)
                return .enqueued(bufferedCount: newPending.count)
            case .ready(let impl):
                return .executeNow(impl)
            }
        }
        switch outcome {
        case .enqueued(let bufferedCount):
            loggerProvider()?.debug(
                "Pre-init event buffer accepted event (buffered count: \(bufferedCount)).",
                Self.logTag
            )
        case .dropped:
            let dropped = droppedCount.mutating { count -> Int in
                count += 1
                return count
            }
            loggerProvider()?.debug(
                "Pre-init event buffer is at capacity (\(capacity)); dropping event. " +
                    "Total dropped this session: \(dropped).",
                Self.logTag
            )
        case .executeNow(let impl):
            block(impl)
        }
    }

    /// Replay all buffered events in order against the provided implementation,
    /// then transition to the `ready` state. Concurrent enqueues that arrive
    /// during the replay are picked up before the transition completes.
    /// Safe to call multiple times; subsequent calls are no-ops once `ready`.
    func transitionToReady(_ implementation: CustomerIOInstance) {
        var totalDrained = 0
        while true {
            let blocksToReplay: [Block] = state.mutating { state -> [Block] in
                switch state {
                case .buffering(let blocks):
                    if blocks.isEmpty {
                        // No buffered events; advance straight to ready so
                        // subsequent enqueues run inline.
                        state = .ready(implementation)
                        return []
                    }
                    state = .draining(implementation, [])
                    return blocks
                case .draining(_, let pending):
                    if pending.isEmpty {
                        state = .ready(implementation)
                        return []
                    }
                    state = .draining(implementation, [])
                    return pending
                case .ready:
                    return []
                }
            }
            if blocksToReplay.isEmpty {
                break
            }
            for block in blocksToReplay {
                block(implementation)
            }
            totalDrained += blocksToReplay.count
        }

        let droppedSnapshot = droppedCount.atomicSetAndFetch(0)
        let logger = loggerProvider()
        logger?.debug(
            "Pre-init event buffer transitioned to ready. Drained \(totalDrained) event(s) " +
                "(dropped due to capacity this session: \(droppedSnapshot)).",
            Self.logTag
        )
    }

    // MARK: - Test-only inspection

    /// Number of currently buffered events not yet drained. Test-only.
    var bufferedCount: Int {
        state.using { state in
            switch state {
            case .buffering(let blocks): return blocks.count
            case .draining(_, let pending): return pending.count
            case .ready: return 0
            }
        }
    }

    /// Whether the buffer has reached the `ready` state. Test-only.
    var isReady: Bool {
        state.using { state in
            if case .ready = state { return true } else { return false }
        }
    }

    /// Number of events dropped due to capacity since the last drain. Test-only.
    var droppedEventCount: Int {
        droppedCount.wrappedValue
    }

    private static let logTag = "PreInitEventBuffer"
}
