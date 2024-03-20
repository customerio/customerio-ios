import CioInternalCommon
import Foundation

class MessagingPushImplementation: MessagingPushInstance {
    let moduleConfig: MessagingPushConfigOptions
    let logger: Logger
    let jsonAdapter: JsonAdapter
    let eventBusHandler: EventBusHandler
    let richPushDeliveryTracker: RichPushDeliveryTracker

    /// testing init
    init(
        moduleConfig: MessagingPushConfigOptions,
        logger: Logger,
        jsonAdapter: JsonAdapter,
        eventBusHandler: EventBusHandler,
        richPushDeliveryTracker: RichPushDeliveryTracker
    ) {
        self.moduleConfig = moduleConfig
        self.logger = logger
        self.jsonAdapter = jsonAdapter
        self.eventBusHandler = eventBusHandler
        self.richPushDeliveryTracker = richPushDeliveryTracker
    }

    init(diGraph: DIGraphShared, moduleConfig: MessagingPushConfigOptions) {
        self.moduleConfig = moduleConfig
        self.logger = diGraph.logger
        self.jsonAdapter = diGraph.jsonAdapter
        self.eventBusHandler = diGraph.eventBusHandler
        self.richPushDeliveryTracker = diGraph.richPushDeliveryTracker
    }

    func deleteDeviceToken() {
        eventBusHandler.postEvent(DeleteDeviceTokenEvent())
    }

    func registerDeviceToken(_ deviceToken: String) {
        eventBusHandler.postEvent(RegisterDeviceTokenEvent(token: deviceToken))
    }

    func trackMetric(deliveryID: String, event: Metric, deviceToken: String) {
        eventBusHandler.postEvent(TrackMetricEvent(deliveryID: deliveryID, event: event.rawValue, deviceToken: deviceToken))
    }

    func trackMetricFromNSE(
        deliveryID: String,
        event: Metric,
        deviceToken: String
    ) {
        richPushDeliveryTracker.trackMetric(token: deviceToken, event: event, deliveryId: deliveryID) { _ in }
    }
}
