import Foundation

/// A push delivery metric queued in the app group before the network request runs (NSE persist-first).
/// Shape aligns with ``MetricRequest`` / “Report Delivery Event” fields used for delivery tracking.
public struct PendingPushDeliveryMetric: Codable, Equatable, Sendable {
    public let id: UUID
    public let deliveryId: String
    public let deviceToken: String
    public let event: Metric
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        deliveryId: String,
        deviceToken: String,
        event: Metric,
        timestamp: Date
    ) {
        self.id = id
        self.deliveryId = deliveryId
        self.deviceToken = deviceToken
        self.event = event
        self.timestamp = timestamp
    }

    enum CodingKeys: String, CodingKey {
        case id
        case deliveryId = "delivery_id"
        case deviceToken = "device_id"
        case event
        case timestamp
    }
}
