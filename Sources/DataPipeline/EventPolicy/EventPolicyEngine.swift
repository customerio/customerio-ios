import CioInternalCommon
import Foundation

/// Synchronous, thread-safe engine that decides whether an event should be
/// allowed through or dropped based on the active ``AggregationRuleset``.
///
/// `@unchecked Sendable` is safe here: all mutable state (`processed`) is
/// protected by `Synchronized<>`, and `StorageManager.db` is serialized
/// internally via a private DispatchQueue.
final class EventPolicyEngine: Sendable {
    // Generates the EventKey for a given event name and type.
    private static func eventKey(eventType: String, name: String) -> String {
        "\(eventType):\(name)"
    }

    /// Generates the EventKey for an event name that matches all named events.
    private static func wildcardEventKey(eventType: String) -> String {
        "\(eventType):*"
    }

    /// Wire-format ruleset pre-processed into O(1) lookup structures.
    private struct ProcessedRuleset {
        /// Keys of the form `"\(eventType):\(name)"` for blocked events.
        let filterKeys: Set<String>
        /// Rate-limit rules keyed by `"\(eventType):\(name)"`. First rule wins on duplicates.
        let rateLimitsByKey: [String: RateLimitEntry]

        init(_ ruleset: AggregationRuleset) {
            self.filterKeys = Set(
                (ruleset.filters ?? []).map {
                    EventPolicyEngine.eventKey(eventType: $0.eventType, name: $0.name)
                }
            )
            self.rateLimitsByKey = Dictionary(
                (ruleset.rateLimits ?? []).map {
                    (EventPolicyEngine.eventKey(eventType: $0.eventType, name: $0.name), $0)
                },
                uniquingKeysWith: { first, _ in first }
            )
        }
    }

    private let storage: StorageManager
    private let processed = Synchronized<ProcessedRuleset?>(nil)

    init(storage: StorageManager) {
        self.storage = storage
    }

    /// Replace the active ruleset. Call this after receiving updated config from the server.
    func load(ruleset: AggregationRuleset?) {
        processed.wrappedValue = ruleset.map { ProcessedRuleset($0) }
    }

    /// Returns `true` if the event is allowed through, `false` if it should be dropped.
    func shouldAllow(eventType: String, name: String) -> Bool {
        shouldAllow(eventType: eventType, name: name, now: Int64(Date().timeIntervalSince1970))
    }

    /// Time-injectable overload used by tests.
    func shouldAllow(eventType: String, name: String, now: Int64) -> Bool {
        guard let ruleSet = processed.wrappedValue else { return true }

        let exactKey = EventPolicyEngine.eventKey(eventType: eventType, name: name)
        let wildcardKey = EventPolicyEngine.wildcardEventKey(eventType: eventType)

        if ruleSet.filterKeys.contains(exactKey) || ruleSet.filterKeys.contains(wildcardKey) {
            return false
        }

        if let rateLimit = ruleSet.rateLimitsByKey[exactKey] ?? ruleSet.rateLimitsByKey[wildcardKey] {
            // Fail open on DB error so a storage failure doesn't silently discard events.
            return
                (try? storage.checkAndUpdateRateLimit(
                    key: exactKey,
                    now: now,
                    windowSeconds: Int64(rateLimit.windowSeconds),
                    scope: rateLimit.scope.rawValue
                )) ?? true
        }

        return true
    }
}
