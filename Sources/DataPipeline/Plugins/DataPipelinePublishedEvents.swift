import CioAnalytics
import CioInternalCommon
import Foundation

/// This class serves as a centralized hub for dispatching events generated from DataPipeline module.
/// It is designed to reduce redundancy and enhance maintainability by funneling these operations through a single plugin.
/// This plugin allows for decoupled modules to subscribe and react to these events.
class DataPipelinePublishedEvents: EventPlugin, Autoresolvable {
    var type: CioAnalytics.PluginType = .before

    var analytics: CioAnalytics.Analytics?
    var eventBusHandler: EventBusHandler

    public required init(resolver: any Resolver) throws {
        self.eventBusHandler = try resolver.resolve()
    }

    public required init(eventBusHandler: EventBusHandler) {
        self.eventBusHandler = eventBusHandler
    }

    func identify(event: IdentifyEvent) -> IdentifyEvent? {
        if let identifier = event.userId ?? event.anonymousId {
            eventBusHandler.postEvent(ProfileIdentifiedEvent(identifier: identifier))
        }
        return event
    }

    func screen(event: ScreenEvent) -> ScreenEvent? {
        if let name = event.name {
            eventBusHandler.postEvent(ScreenViewedEvent(name: name))
        }
        return event
    }

    func reset() {
        eventBusHandler.postEvent(ResetEvent())
    }
}
