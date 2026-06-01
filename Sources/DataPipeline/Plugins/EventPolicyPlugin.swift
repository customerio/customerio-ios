import CioAnalytics
import CioInternalCommon

class EventPolicyPlugin: EventPlugin {
    let type = PluginType.enrichment
    weak var analytics: Analytics?
    private let engine: EventPolicyEngine

    init(engine: EventPolicyEngine) {
        self.engine = engine
    }

    func update(settings: Settings, type: UpdateType) {
        struct IntegrationSettings: Codable {
            let aggregationRules: AggregationRuleset?
        }
        let config: IntegrationSettings? = settings.integrationSettings(forKey: "Customer.io Data Pipelines")
        engine.load(ruleset: config?.aggregationRules)
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
