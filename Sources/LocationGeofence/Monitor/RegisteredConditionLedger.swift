import CioInternalCommon
import Foundation

/// A condition as this process registered it at the OS.
struct RegisteredCondition: Equatable {
    let center: LocationData
    let radius: Double
    let transitionTypes: Set<GeofenceTransition>
    /// When this condition was STAGED. Registration records geometry synchronously so a sync
    /// landing before the queued add drains still diffs against it.
    var registeredAt: Date = .distantPast
    /// When the OS actually began evaluating this circle — the moment the queued remove+add
    /// drained. Nil until then, and until then the OS is still evaluating the circle this one
    /// replaced, so an event raised now belongs to that one and not to this.
    var liveFrom: Date?

    /// Geometry only. `registeredAt` is bookkeeping about WHEN, and the baseline heal compares
    /// conditions to ask whether the circle still matches — a re-registration of the same circle
    /// must not read as a change there.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.center == rhs.center && lhs.radius == rhs.radius
            && lhs.transitionTypes == rhs.transitionTypes
    }
}

/// What the ledger can say about the circle an event was raised against.
///
/// `noneHeld` and `expired` are kept apart because a consumer must answer them differently, and
/// collapsing both to nil is what let a stale exit be treated as current.
enum EventAttribution: Equatable {
    /// The circle the OS was evaluating when the event was raised.
    case generation(RegisteredCondition)
    /// Nothing this ledger holds covers the event, and nothing ever went live for the identifier —
    /// a cold wake, where the OS evaluates a condition this process never recorded. The event has
    /// to be taken as current: refusing every one of them would drop real crossings.
    case noneHeld
    /// Generations went live for this identifier and the event predates all of them, so the circle
    /// it was raised against is one the ledger no longer holds. The opposite of `noneHeld`: here
    /// the staleness is known, and any claim the event makes about the fence's geometry is void.
    case expired
}

/// What this process has asked the OS to monitor, and what the OS is actually monitoring.
///
/// Those are different things, and attribution depends on the second: registrations are recorded
/// synchronously but reach the OS through a serial queue, so between staging and drain the OS is
/// still evaluating the circle being replaced. Staged generations are therefore held until their
/// own add drains rather than replacing each other, because two can stage before the first drains
/// and the one the OS takes next is the OLDEST queued, not the newest staged.
///
/// A plain value type so the register → replace → late-event sequence can be exercised directly:
/// `CLMonitorGeofenceMonitor` builds a `CLLocationManager` and cannot be created in a unit test, and
/// testing the selection in isolation is how a version of this shipped where nothing ever populated
/// the previous generation.
struct RegisteredConditionLedger {
    private struct Entry {
        /// The latest staged registration — what geometry comparisons diff against. Cleared by
        /// `retire`; the live generations below survive it, since an event the daemon already
        /// raised can still be dequeued after this process gives up its claim.
        var staged: RegisteredCondition?
        /// Staged and awaiting their OS add, oldest first. FIFO, because the monitor's operations
        /// drain in the order they were enqueued.
        var queued: [RegisteredCondition] = []
        /// The circle the OS is evaluating now, and the one it evaluated before that. Two is
        /// enough: an event is dequeued from the stream within an async hop of being raised, so it
        /// cannot predate the generation before the current one.
        var live: RegisteredCondition?
        var previouslyLive: RegisteredCondition?
    }

    private var entries: [String: Entry] = [:]

    /// Records the circle a condition now holds.
    ///
    /// `liveFrom` non-nil means the OS is already evaluating it — adoption, where the condition
    /// outlived the process — so it goes straight to live and cancels anything queued behind it.
    mutating func note(
        identifier: String,
        center: LocationData,
        radius: Double,
        transitionTypes: Set<GeofenceTransition>,
        at registeredAt: Date,
        liveFrom: Date? = nil
    ) {
        let condition = RegisteredCondition(
            center: center, radius: radius, transitionTypes: transitionTypes,
            registeredAt: registeredAt, liveFrom: liveFrom
        )
        var entry = entries[identifier] ?? Entry()
        entry.staged = condition
        if liveFrom != nil {
            entry.queued.removeAll()
            entry.previouslyLive = entry.live
            entry.live = condition
        } else {
            entry.queued.append(condition)
        }
        entries[identifier] = entry
    }

    /// Records that the OS has taken this circle, which is what makes it the one events belong to.
    ///
    /// Keyed on `stagedAt` so a drain promotes the generation it belongs to rather than whichever
    /// is newest: with two staged, the first add to drain makes the FIRST circle live, and the
    /// second stays queued until its own add lands.
    mutating func confirm(_ identifier: String, stagedAt: Date, at liveFrom: Date) {
        guard var entry = entries[identifier],
              let index = entry.queued.firstIndex(where: { $0.registeredAt == stagedAt })
        else { return }
        var confirmed = entry.queued[index]
        confirmed.liveFrom = liveFrom
        // Anything queued ahead of this one can no longer drain — the queue is serial and this add
        // came off it — so dropping them keeps the queue from growing on a path that never fires.
        entry.queued.removeSubrange(...index)
        entry.previouslyLive = entry.live
        entry.live = confirmed
        entries[identifier] = entry
    }

    /// Gives up the claim on a condition without forgetting what the OS is evaluating.
    mutating func retire(_ identifier: String) {
        entries[identifier]?.staged = nil
    }

    /// The OS gave the condition up. `.unmonitored` arrives on the same sequential event stream as
    /// the crossings, so every earlier event for this id has already been dequeued and none can be
    /// in flight — and dropping everything is also what stops a stale circle surviving a teardown
    /// to misattribute the next session's events.
    mutating func forget(_ identifier: String) {
        entries[identifier] = nil
    }

    mutating func forgetAll() {
        entries.removeAll()
    }

    func condition(for identifier: String) -> RegisteredCondition? {
        entries[identifier]?.staged
    }

    /// The circle an event raised at `raisedAt` was evaluated against, chosen by the event's own
    /// date rather than by what is registered now: `CLMonitor` events are read off an async stream
    /// and the handler awaits a fix request and a storage write before asking, so registrations can
    /// drain in between and the current one need not be the one the event crossed.
    ///
    /// Read from the live generations only. A staged circle the OS has not taken yet has never
    /// produced an event, so attributing one to it is the mistake this exists to prevent.
    func attribution(for identifier: String, raisedAt: Date) -> EventAttribution {
        guard let entry = entries[identifier] else { return .noneHeld }
        if let live = entry.live, let liveFrom = live.liveFrom, raisedAt >= liveFrom {
            return .generation(live)
        }
        if let previous = entry.previouslyLive, let previousFrom = previous.liveFrom,
           raisedAt >= previousFrom {
            return .generation(previous)
        }
        // Nothing has drained yet, so this ledger has never known what the OS is evaluating and
        // cannot call the event stale — only a generation that WENT live can expire.
        guard entry.live != nil else { return .noneHeld }
        return .expired
    }
}
