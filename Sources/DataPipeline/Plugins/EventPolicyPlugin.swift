import CioAnalytics
import CioInternalCommon
import Foundation

class EventPolicyPlugin: EventPlugin {
    let type = PluginType.enrichment
    weak var analytics: Analytics?
    private let engine: EventPolicyEngine
    private let storage: StorageManager?

    init(engine: EventPolicyEngine, storage: StorageManager?) {
        self.engine = engine
        self.storage = storage
    }

    func update(settings: Settings, type: UpdateType) {
        struct IntegrationSettings: Codable {
            let aggregationRules: AggregationRuleset?
        }
        let config: IntegrationSettings? = settings.integrationSettings(forKey: "Customer.io Data Pipelines")
        let ruleset = config?.aggregationRules
        engine.load(ruleset: ruleset)

        if let ruleset,
           let json = try? JSONEncoder().encode(ruleset),
           let payload = String(data: json, encoding: .utf8) {
            let fetchedAt = ISO8601DateFormatter().string(from: Date())
            try? storage?.setAggregationConfig(payload: payload, fetchedAt: fetchedAt)
        }
    }

    func track(event: TrackEvent) -> TrackEvent? {
        engine.shouldAllow(eventType: "track", name: event.event) ? event : nil
    }

    func screen(event: ScreenEvent) -> ScreenEvent? {
        engine.shouldAllow(eventType: "screen", name: event.name ?? "") ? event : nil
    }

    func identify(event: IdentifyEvent) -> IdentifyEvent? {
        engine.shouldAllow(eventType: "identify", name: "*") ? event : nil
    }

    // Unused, but required
    func alias(event: AliasEvent) -> AliasEvent? {
        engine.shouldAllow(eventType: "alias", name: event.userId ?? "") ? event : nil
    }

    // Unused, but required
    func group(event: GroupEvent) -> GroupEvent? {
        engine.shouldAllow(eventType: "group", name: event.groupId ?? "") ? event : nil
    }
}
