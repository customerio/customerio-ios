import CioInternalCommon
import Foundation

/// A condition as this process registered it at the OS.
struct RegisteredCondition: Equatable {
    let center: LocationData
    let radius: Double
    let transitionTypes: Set<GeofenceTransition>
    /// When this condition replaced whatever was registered under the same id. Lets an event be
    /// attributed to the circle that was live when the daemon raised it, rather than to whatever is
    /// live when we get round to reading it.
    var registeredAt: Date = .distantPast

    /// Geometry only. `registeredAt` is bookkeeping about WHEN, and the baseline heal compares
    /// conditions to ask whether the circle still matches — a re-registration of the same circle
    /// must not read as a change there.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.center == rhs.center && lhs.radius == rhs.radius
            && lhs.transitionTypes == rhs.transitionTypes
    }
}

/// The circles this process has registered, and one generation back for each.
///
/// A plain value type so the register → replace → late-event sequence can be exercised directly:
/// `CLMonitorGeofenceMonitor` builds a `CLLocationManager` and cannot be created in a unit test, and
/// testing the selection in isolation is how a version of this shipped where nothing ever populated
/// the previous generation.
///
/// One generation deep is enough. A second replacement means the OS re-evaluated in between, so
/// anything still queued from two back is already superseded.
struct RegisteredConditionLedger {
    private(set) var current: [String: RegisteredCondition] = [:]
    private(set) var previous: [String: RegisteredCondition] = [:]

    /// Records the circle a condition now holds, keeping what it replaced.
    ///
    /// A missing current entry does NOT clear `previous`: `setMonitoredRegions` releases ownership
    /// before re-registering, so by the time this runs the superseded generation is already in
    /// `previous` and must survive. Ordering between `retire` and `note` therefore cannot change
    /// the outcome, which is the point — the two being ordered the other way is what made an
    /// earlier version of this attribution inert.
    mutating func note(
        identifier: String,
        center: LocationData,
        radius: Double,
        transitionTypes: Set<GeofenceTransition>,
        at registeredAt: Date
    ) {
        if let superseded = current[identifier] { previous[identifier] = superseded }
        current[identifier] = RegisteredCondition(
            center: center, radius: radius, transitionTypes: transitionTypes, registeredAt: registeredAt
        )
    }

    /// Gives up the claim on a condition while keeping its circle for attribution: an event the
    /// daemon already raised against it can still be dequeued after this.
    mutating func retire(_ identifier: String) {
        if let released = current.removeValue(forKey: identifier) { previous[identifier] = released }
    }

    /// The OS gave the condition up, so nothing queued for it should be attributed to this process
    /// afterwards — both generations go, rather than the current one retiring into the previous.
    mutating func forget(_ identifier: String) {
        current.removeValue(forKey: identifier)
        previous.removeValue(forKey: identifier)
    }

    mutating func forgetAll() {
        current.removeAll()
        previous.removeAll()
    }

    func condition(for identifier: String) -> RegisteredCondition? {
        current[identifier]
    }

    /// The circle an event raised at `raisedAt` was evaluated against, chosen by the event's own
    /// date rather than by what is registered now: `CLMonitor` events are read off an async stream,
    /// so a refresh can replace the condition between the daemon raising an event and this process
    /// dequeuing it.
    ///
    /// Nil when nothing is registered, or when the event predates the current registration and no
    /// previous generation is held. A consumer reads nil as "cannot say" and treats the event as
    /// current, which is why adoption seeds `.distantPast`: a condition inherited from before this
    /// process started predates every event it will see.
    func circle(for identifier: String, raisedAt: Date) -> RegisteredCondition? {
        guard let live = current[identifier] else { return nil }
        return raisedAt < live.registeredAt ? previous[identifier] : live
    }
}
