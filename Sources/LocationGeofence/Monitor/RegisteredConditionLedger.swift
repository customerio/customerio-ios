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
    /// When the OS began evaluating this circle: the instant its queued add was issued, since the
    /// daemon dates its corrective event as the add lands. Nil until then, while the OS still holds
    /// the circle this one replaces.
    var liveFrom: Date?

    /// Geometry only: callers compare conditions to ask whether the circle still matches, and a
    /// re-registration of the same circle must not read as a change.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.center == rhs.center && lhs.radius == rhs.radius
            && lhs.transitionTypes == rhs.transitionTypes
    }
}

/// What the ledger can say about the circle an event was raised against.
///
/// `noneHeld` and `expired` are kept apart because a consumer must answer them differently;
/// collapsing them would let a stale exit be treated as current.
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
/// Attribution depends on the second: registrations are recorded synchronously but reach the OS
/// through a serial queue, so between staging and drain the OS still evaluates the old circle.
/// Staged generations are held until their own add drains, because two can stage before the first
/// drains and the OS takes the OLDEST queued next, not the newest staged.
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
    /// the crossings, so no earlier event for this id can still be in flight.
    mutating func forget(_ identifier: String) {
        entries[identifier] = nil
    }

    /// Teardown: drops live generations too, so a stale circle cannot misattribute the next
    /// session's events.
    mutating func forgetAll() {
        entries.removeAll()
    }

    func condition(for identifier: String) -> RegisteredCondition? {
        entries[identifier]?.staged
    }

    /// Every condition this process currently wants the OS to hold.
    ///
    /// Keyed on `staged`, not `live`: `retire` clears the claim but deliberately keeps the live
    /// generations, so a condition removed on purpose would otherwise keep reading as wanted long
    /// after its remove drained.
    var stagedIdentifiers: Set<String> {
        Set(entries.filter { $0.value.staged != nil }.keys)
    }

    /// The circle an event raised at `raisedAt` was evaluated against, chosen by the event's date:
    /// events are read off an async stream and the handler awaits before asking, so registrations
    /// can drain in between. Live generations only; a staged circle has never produced an event.
    func attribution(for identifier: String, raisedAt: Date) -> EventAttribution {
        guard let entry = entries[identifier] else { return .noneHeld }
        if let live = entry.live, let liveFrom = live.liveFrom, raisedAt >= liveFrom {
            return .generation(live)
        }
        if let previous = entry.previouslyLive, let previousFrom = previous.liveFrom,
           raisedAt >= previousFrom {
            return .generation(previous)
        }
        // Only a REPLACED generation can be known stale. With no previous one, an earlier event
        // was raised against a condition held before this process registered anything (adoption
        // did not run), whose circle may well be the current one.
        guard entry.previouslyLive != nil else { return .noneHeld }
        return .expired
    }
}
