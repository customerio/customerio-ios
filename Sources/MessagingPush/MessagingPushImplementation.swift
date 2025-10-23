import CioInternalCommon
import Foundation

class MessagingPushImplementation: MessagingPushInstance {
    let moduleConfig: MessagingPushConfigOptions
    let logger: Logger
    let pushLogger: PushNotificationLogger
    let jsonAdapter: JsonAdapter
    let eventBusHandler: EventBusHandler

    init(diGraph: DIGraphShared, moduleConfig: MessagingPushConfigOptions) {
        self.moduleConfig = moduleConfig
        self.logger = diGraph.logger
        self.jsonAdapter = diGraph.jsonAdapter
        self.eventBusHandler = diGraph.eventBusHandler
        self.pushLogger = diGraph.pushNotificationLogger
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
        // Access richPushDeliveryTracker from DIGraphShared.shared directly as it is only required for NSE.
        // Keeping it as class property results in initialization of UserAgentUtil before SDK client is overridden by wrapper SDKs.
        // In future, we can improve how we access SdkClient so that we don't need to worry about initialization order.
        DIGraphShared.shared.richPushDeliveryTracker.trackMetric(token: deviceToken, event: event, deliveryId: deliveryID, timestamp: nil) { result in
            switch result {
            case .success:
                self.pushLogger.logPushMetricTracked(deliveryId: deliveryID, event: event.rawValue)
            case .failure(let error):
                self.pushLogger.logPushMetricTrackingFailed(deliveryId: deliveryID, event: event.rawValue, error: error)
            }
        }
    }
}
