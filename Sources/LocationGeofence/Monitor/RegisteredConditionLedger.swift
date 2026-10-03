import CioInternalCommon
import Foundation

struct RegisteredCondition: Equatable {
    let center: LocationData
    let radius: Double
    let transitionTypes: Set<GeofenceTransition>
    /// When STAGED, not when the OS took it (see `liveFrom`).
    var registeredAt: Date = .distantPast
    /// When its queued add was issued (the daemon dates its corrective as the add lands). Nil while
    /// the OS still holds the circle this one replaces.
    var liveFrom: Date?

    /// Geometry only, so re-registering the same circle doesn't read as a change.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.center == rhs.center && lhs.radius == rhs.radius
            && lhs.transitionTypes == rhs.transitionTypes
    }
}

/// Keep `noneHeld` and `expired` apart: collapsing them would let a stale exit be treated as current.
enum EventAttribution: Equatable {
    case generation(RegisteredCondition)
    /// Nothing went live for the id (cold wake). Must be taken as current, or real crossings drop.
    case noneHeld
    /// The event predates every live generation, so its circle is known stale.
    case expired
}

/// Staging is synchronous but the OS add drains later, so attribution tracks what the OS evaluates.
/// Generations stay queued until their own add drains: the OS takes the OLDEST queued next.
struct RegisteredConditionLedger {
    private struct Entry {
        /// Cleared by `retire`; live generations survive it, since an already-raised event can
        /// still be dequeued after the claim is given up.
        var staged: RegisteredCondition?
        var queued: [RegisteredCondition] = []
        /// Two is enough: an event is dequeued within an async hop of being raised.
        var live: RegisteredCondition?
        var previouslyLive: RegisteredCondition?
    }

    private var entries: [String: Entry] = [:]

    /// `liveFrom` non-nil (adoption): the OS already evaluates it, so it goes straight to live.
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

    /// Keyed on `stagedAt`, so a drain promotes its own generation, not the newest staged.
    mutating func confirm(_ identifier: String, stagedAt: Date, at liveFrom: Date) {
        guard var entry = entries[identifier],
              let index = entry.queued.firstIndex(where: { $0.registeredAt == stagedAt })
        else { return }
        var confirmed = entry.queued[index]
        confirmed.liveFrom = liveFrom
        // Anything queued ahead can no longer drain (the queue is serial).
        entry.queued.removeSubrange(...index)
        entry.previouslyLive = entry.live
        entry.live = confirmed
        entries[identifier] = entry
    }

    /// Gives up the claim without forgetting what the OS is evaluating.
    mutating func retire(_ identifier: String) {
        entries[identifier]?.staged = nil
    }

    /// `.unmonitored` arrives on the same sequential stream as crossings, so no earlier event for
    /// this id can still be in flight.
    mutating func forget(_ identifier: String) {
        entries[identifier] = nil
    }

    /// Drops live generations too, so a stale circle can't misattribute the next session's events.
    mutating func forgetAll() {
        entries.removeAll()
    }

    func condition(for identifier: String) -> RegisteredCondition? {
        entries[identifier]?.staged
    }

    /// Keyed on `staged`, not `live`: `retire` keeps live generations, so a removed condition would
    /// keep reading as wanted.
    var stagedIdentifiers: Set<String> {
        Set(entries.filter { $0.value.staged != nil }.keys)
    }

    /// By the event's date: registrations can drain between raise and handling. Live generations only.
    func attribution(for identifier: String, raisedAt: Date) -> EventAttribution {
        guard let entry = entries[identifier] else { return .noneHeld }
        if let live = entry.live, let liveFrom = live.liveFrom, raisedAt >= liveFrom {
            return .generation(live)
        }
        if let previous = entry.previouslyLive, let previousFrom = previous.liveFrom,
           raisedAt >= previousFrom {
            return .generation(previous)
        }
        // Only a REPLACED generation can be known stale; otherwise an earlier event's circle may
        // well be the current one.
        guard entry.previouslyLive != nil else { return .noneHeld }
        return .expired
    }
}
