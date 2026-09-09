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
    /// replaced, so an event raised now belongs to the previous generation and not to this.
    var liveFrom: Date?

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
        at registeredAt: Date,
        liveFrom: Date? = nil
    ) {
        if let superseded = current[identifier] { previous[identifier] = superseded }
        current[identifier] = RegisteredCondition(
            center: center, radius: radius, transitionTypes: transitionTypes,
            registeredAt: registeredAt, liveFrom: liveFrom
        )
    }

    /// Records that the OS has taken this circle, which is what makes it the one events belong to.
    ///
    /// Keyed on `stagedAt` so a drain can only confirm the generation it belongs to: registrations
    /// stage synchronously but drain later, so a second staging can land before the first add
    /// drains, and an unkeyed confirm would mark the newer circle live from the older add.
    mutating func confirm(_ identifier: String, stagedAt: Date, at liveFrom: Date) {
        guard var live = current[identifier], live.registeredAt == stagedAt, live.liveFrom == nil else { return }
        live.liveFrom = liveFrom
        current[identifier] = live
    }

    /// Gives up the claim on a condition while keeping its circle for attribution: an event the
    /// daemon already raised against it can still be dequeued after this.
    mutating func retire(_ identifier: String) {
        if let released = current.removeValue(forKey: identifier) { previous[identifier] = released }
    }

    /// The OS gave the condition up. `.unmonitored` arrives on the same sequential event stream as
    /// the crossings, so every earlier event for this id has already been dequeued and none can be
    /// in flight — and dropping both generations is also what stops a stale circle surviving a
    /// teardown to misattribute the next session's events.
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
    /// Compared against `liveFrom`, not the staging time: between staging and drain the OS is still
    /// evaluating the circle being replaced, so an event raised in that window belongs to the
    /// previous generation even though it postdates the new registration.
    ///
    /// Nil when nothing is registered, or when the event belongs to a previous generation that is
    /// not held. A consumer reads nil as "cannot say" and treats the event as current, which is why
    /// adoption passes `liveFrom: .distantPast`: the OS was already evaluating that circle before
    /// this process existed.
    func circle(for identifier: String, raisedAt: Date) -> RegisteredCondition? {
        guard let live = current[identifier] else { return nil }
        guard let liveFrom = live.liveFrom, raisedAt >= liveFrom else { return previous[identifier] }
        return live
    }
}
