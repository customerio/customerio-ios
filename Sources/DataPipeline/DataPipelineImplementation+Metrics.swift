import CioAnalytics
import CioInternalCommon
import Foundation

// Push and in-app delivery metrics.
extension DataPipelineImplementation {
    func trackDeliveryEvent(token: String?, event: String, deliveryId: String, timestamp: String) {
        processMetricsFromBGQ(token: token, event: event, deliveryId: deliveryId, timestamp: timestamp, metaData: [:])
    }

    func trackMetric(deliveryID: String, event: Metric, deviceToken: String) {
        trackPushMetric(deliveryID: deliveryID, event: event.rawValue, deviceToken: deviceToken)
    }

    func trackPushMetric(deliveryID: String, event: String, deviceToken: String) {
        logger.info("push metric \(event)")

        logger.debug("delivery id \(deliveryID) device token \(deviceToken)")

        trackMetricEvent(deliveryID: deliveryID, event: event, deviceToken: deviceToken)
    }

    func trackInAppMetric(deliveryID: String, event: String, metaData: [String: String]) {
        logger.info("in-app metric \(event)")

        logger.debug("delivery id \(deliveryID) metaData \(metaData)")

        trackMetricEvent(deliveryID: deliveryID, event: event, metaData: metaData)
    }

    /// Tracks metric events for push and in-app messages
    private func trackMetricEvent(deliveryID: String, event: String, deviceToken: String? = nil, metaData: [String: String] = [:]) {
        // property keys should be camelCase
        var properties: [String: String] = metaData

        properties["metric"] = event
        properties["deliveryId"] = deliveryID

        if let token = deviceToken {
            properties["recipient"] = token
        }

        analytics.track(name: "Report Delivery Event", properties: properties)
    }
}
