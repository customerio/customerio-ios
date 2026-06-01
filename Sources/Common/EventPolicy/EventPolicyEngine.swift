import Foundation

/// Synchronous, thread-safe engine that decides whether an event should be
/// allowed through or dropped based on the active ``AggregationRuleset``.
///
/// `@unchecked Sendable` is safe here: all mutable state (`processed`) is
/// protected by `Synchronized<>`, and `StorageManager.db` is serialized
/// internally via a private DispatchQueue.
public final class EventPolicyEngine: Sendable {

    /// Wire-format ruleset pre-processed into O(1) lookup structures.
    private struct ProcessedRuleset {
        /// Keys of the form `"\(eventType):\(name)"` for blocked events.
        let filterKeys: Set<String>
        /// Rate-limit rules keyed by `"\(eventType):\(name)"`. First rule wins on duplicates.
        let rateLimitsByKey: [String: RateLimitEntry]

        init(_ ruleset: AggregationRuleset) {
            filterKeys = Set((ruleset.filters ?? []).map { "\($0.eventType):\($0.name)" })
            rateLimitsByKey = Dictionary(
                (ruleset.rateLimits ?? []).map { ("\($0.eventType):\($0.name)", $0) },
                uniquingKeysWith: { first, _ in first }
            )
        }
    }

    private let storage: StorageManager
    private let processed = Synchronized<ProcessedRuleset?>(nil)

    public init(storage: StorageManager) {
        self.storage = storage
    }

    /// Replace the active ruleset. Call this after receiving updated config from the server.
    public func load(ruleset: AggregationRuleset?) {
        processed.wrappedValue = ruleset.map { ProcessedRuleset($0) }
    }

    /// Returns `true` if the event is allowed through, `false` if it should be dropped.
    public func shouldAllow(eventType: String, name: String) -> Bool {
        shouldAllow(eventType: eventType, name: name, now: Int64(Date().timeIntervalSince1970))
    }

    /// Time-injectable overload used by tests.
    func shouldAllow(eventType: String, name: String, now: Int64) -> Bool {
        guard let rs = processed.wrappedValue else { return true }

        let exactKey = "\(eventType):\(name)"
        let wildcardKey = "\(eventType):*"

        if rs.filterKeys.contains(exactKey) || rs.filterKeys.contains(wildcardKey) {
            return false
        }

        if let rl = rs.rateLimitsByKey[exactKey] ?? rs.rateLimitsByKey[wildcardKey] {
            // Use the rule's own key as the DB key so wildcard rules share one counter
            // across all events of that type (e.g. "track:*" is one shared window).
            let dbKey = "\(rl.eventType):\(rl.name)"
            // Fail open on DB error so a storage failure doesn't silently discard events.
            return (try? storage.checkAndUpdateRateLimit(
                key: dbKey,
                now: now,
                windowSeconds: Int64(rl.windowSeconds),
                scope: rl.scope.rawValue
            )) ?? true
        }

        return true
    }
}