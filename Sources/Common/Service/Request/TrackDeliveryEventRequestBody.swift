import Foundation

internal struct TrackDeliveryEventRequestBody: Codable {
    internal let type: DeliveryType
    internal let payload: DeliveryPayload

    enum CodingKeys: String, CodingKey {
        case type
        case payload
    }
}

internal struct DeliveryPayload: Codable {
    internal let deliveryId: String
    internal let event: InAppMetric
    internal let timestamp: Date
    internal let metaData: [String: String]

    enum CodingKeys: String, CodingKey {
        case deliveryId = "delivery_id"
        case event
        case timestamp
        case metaData = "metadata"
    }
}

internal enum DeliveryType: String, Codable {
    case inApp = "in_app"
}
