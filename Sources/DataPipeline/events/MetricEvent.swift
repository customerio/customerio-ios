import CioInternalCommon
import Segment

/// An extension of Segment's RawEvent to track push and in-app metrics
class MetricEvent: RawEvent {
    public var type: String? = "track"
    public var anonymousId: String?
    public var messageId: String?
    public var userId: String?
    public var timestamp: String?
    public var context: JSON?
    public var integrations: JSON?
    public var metrics: [JSON]?
    public var _metadata: DestinationMetadata?

    public var event: String
    public var properties: JSON?

    public init(event: String, metric: Metric, deliveryId: String, deliveryToken: String) {
        self.event = event
        // FIXME: [CDP] Update JSON to match the server's expectation
        let properties = [
            "event": metric.rawValue,
            "deliveryId": deliveryId,
            "deliveryToken": deliveryToken
        ]
        self.properties = try? JSON(properties)
    }
}
