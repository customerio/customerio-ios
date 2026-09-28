import CioInternalCommon
import Foundation

/// Per-user event cooldowns, split out to keep `GeofenceStorage` readable. Methods are `internal`
/// (not `private`) only because they live in a separate file from their state; each still runs its
/// load → modify → save inside the actor with no `await` between steps.
extension GeofenceStorage {
    func getEventCooldowns() -> [String: Date] {
        loadFromDisk()?.eventCooldowns ?? [:]
    }

    func recordEventCooldown(key: String, timestamp: Date) {
        var state = loadFromDisk() ?? GeofenceState()
        var cooldowns = state.eventCooldowns ?? [:]
        cooldowns[key] = timestamp
        state.eventCooldowns = cooldowns
        saveToDisk(state)
    }

    /// Atomically checks whether the cooldown window for `key` has expired and, if so,
    /// records the new timestamp. Returns `true` when the caller may proceed (no active
    /// cooldown), `false` when the event should be suppressed. The whole check-and-record
    /// runs inside the actor with no `await` between steps, so concurrent callers cannot
    /// both observe an expired window and both fire the event.
    /// `nil` when the cooldown was acquired. Otherwise the seconds still left on it — a value the
    /// check already computes, returned rather than recomputed, so reporting it costs no second
    /// load of the store on a background wake.
    func tryAcquireCooldown(key: String, now: Date, interval: TimeInterval) -> TimeInterval? {
        var state = loadFromDisk() ?? GeofenceState()
        var cooldowns = state.eventCooldowns ?? [:]
        if let last = cooldowns[key] {
            let elapsed = now.timeIntervalSince(last)
            if elapsed < interval { return interval - elapsed }
        }
        cooldowns[key] = now
        state.eventCooldowns = cooldowns
        saveToDisk(state)
        return nil
    }

    /// Atomically removes cooldown entries whose recorded timestamp is older than `interval`
    /// before `now`. Filtering happens inside the actor so a concurrent `tryAcquireCooldown`
    /// cannot have its fresh write deleted by a stale snapshot.
    func purgeExpiredCooldowns(now: Date, interval: TimeInterval) {
        var state = loadFromDisk() ?? GeofenceState()
        guard var cooldowns = state.eventCooldowns, !cooldowns.isEmpty else { return }
        let beforeCount = cooldowns.count
        cooldowns = cooldowns.filter { now.timeIntervalSince($0.value) < interval }
        if cooldowns.count == beforeCount { return }
        state.eventCooldowns = cooldowns
        saveToDisk(state)
    }

    /// Removes the cooldown entry for `key`, if present. Called when persist-first fails after the
    /// cooldown was already claimed, so the next transition of this type isn't suppressed against a
    /// metric that never reached the pending queue.
    func releaseCooldown(key: String) {
        var state = loadFromDisk() ?? GeofenceState()
        guard var cooldowns = state.eventCooldowns, cooldowns.removeValue(forKey: key) != nil else { return }
        state.eventCooldowns = cooldowns
        saveToDisk(state)
    }

    func clearEventCooldowns() {
        var state = loadFromDisk() ?? GeofenceState()
        state.eventCooldowns = nil
        saveToDisk(state)
    }
}
