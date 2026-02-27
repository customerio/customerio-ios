import CioAnalytics
import CioInternalCommon
import Foundation

/// Segment plugin that adds fields to the identify event context by delegating to registered profile enrichment providers.
///
/// On identify: queries all providers for attributes and adds them to the event context
/// (primitives only).
///
/// This plugin has zero knowledge of specific modules — providers manage their own state
/// and return primitive-valued maps.
class IdentifyContextPlugin: EventPlugin {
    var type: PluginType = .enrichment
    weak var analytics: Analytics?

    private let registry: ProfileEnrichmentRegistry
    private let logger: Logger

    init(registry: ProfileEnrichmentRegistry, logger: Logger) {
        self.registry = registry
        self.logger = logger
    }

    func identify(event: IdentifyEvent) -> IdentifyEvent? {
        let enrichment = ProfileEnrichmentAttributesMerger.gatherEnrichmentAttributes(registry: registry)
        guard !enrichment.isEmpty else { return event }

        var workingEvent = event
        var context = workingEvent.context?.dictionaryValue ?? [:]

        do {
            for (key, value) in enrichment {
                context[key] = value
            }
            workingEvent.context = try JSON(context)
        } catch {
            logger.error("IdentifyContextPlugin failed to add context: \(error.localizedDescription)")
            return event
        }
        return workingEvent
    }

    func reset() {
        // Clear provider caches synchronously so the next identify() does not see stale context
        // (e.g. previous profile's location). ResetEvent remains for async module cleanup.
        for provider in registry.getAll() {
            provider.resetContext()
        }
    }
}
