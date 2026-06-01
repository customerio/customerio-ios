import Foundation

/// Synchronous, thread-safe engine that decides whether an event should be
/// allowed through or dropped based on the active ``AggregationRuleset``.
///
/// `@unchecked Sendable` is safe here: all mutable state (`ruleset`) is
/// protected by `Synchronized<>`, and `StorageManager.db` is serialized
/// internally via a private DispatchQueue.
public final class EventPolicyEngine: Sendable {

    private let storage: StorageManager
    private let ruleset = Synchronized<AggregationRuleset?>(nil)

    public init(storage: StorageManager) {
        self.storage = storage
    }

    /// Replace the active ruleset. Call this after receiving updated config from the server.
    public func load(ruleset: AggregationRuleset?) {
        self.ruleset.wrappedValue = ruleset
    }

    /// Returns `true` if the event is allowed through, `false` if it should be dropped.
    public func shouldAllow(eventType: String, name: String) -> Bool {
        shouldAllow(eventType: eventType, name: name, now: Int64(Date().timeIntervalSince1970))
    }

    /// Time-injectable overload used by tests.
    func shouldAllow(eventType: String, name: String, now: Int64) -> Bool {
        guard let rs = ruleset.wrappedValue else { return true }

        if let filters = rs.filters {
            for f in filters where f.eventType == eventType && (f.name == "*" || f.name == name) {
                return false
            }
        }

        if let rateLimits = rs.rateLimits {
            for rl in rateLimits where rl.eventType == eventType && (rl.name == "*" || rl.name == name) {
                let key = "\(rl.eventType):\(rl.name)"
                // Fail open on DB error so a storage failure doesn't silently discard events.
                return (try? storage.checkAndUpdateRateLimit(
                    key: key,
                    now: now,
                    windowSeconds: Int64(rl.windowSeconds),
                    scope: rl.scope.rawValue
                )) ?? true
            }
        }

        return true
    }
}