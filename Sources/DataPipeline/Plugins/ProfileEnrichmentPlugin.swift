import CioAnalytics
import CioInternalCommon
import Foundation

/// Segment enrichment plugin that delegates to registered profile enrichment providers.
///
/// On identify: queries all providers for attributes and adds them to the event context
/// (primitives only).
///
/// This plugin has zero knowledge of specific modules — providers manage their own state
/// and return primitive-valued maps.
class ProfileEnrichmentPlugin: EventPlugin {
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
            logger.error("ProfileEnrichmentPlugin failed to add context: \(error.localizedDescription)")
            return event
        }
        return workingEvent
    }

    func reset() {
        // No state to clear; providers clear their own state via ResetEvent.
    }
}
