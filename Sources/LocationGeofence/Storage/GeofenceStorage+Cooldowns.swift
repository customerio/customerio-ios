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

    /// Checks and records in one step, so concurrent callers can't both fire.
    /// - Returns: `nil` when acquired, otherwise the seconds still left on the cooldown.
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

    /// Filtered inside the actor so a concurrent `tryAcquireCooldown` write can't be lost.
    func purgeExpiredCooldowns(now: Date, interval: TimeInterval) {
        var state = loadFromDisk() ?? GeofenceState()
        guard var cooldowns = state.eventCooldowns, !cooldowns.isEmpty else { return }
        let beforeCount = cooldowns.count
        cooldowns = cooldowns.filter { now.timeIntervalSince($0.value) < interval }
        if cooldowns.count == beforeCount { return }
        state.eventCooldowns = cooldowns
        saveToDisk(state)
    }

    /// For when persisting fails after the claim, so the next transition isn't suppressed.
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
