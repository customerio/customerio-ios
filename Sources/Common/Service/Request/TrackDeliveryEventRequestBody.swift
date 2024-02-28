import Foundation

public struct TrackDeliveryEventRequestBody: Codable {
    let type: DeliveryType
    public let payload: DeliveryPayload

    enum CodingKeys: String, CodingKey {
        case type
        case payload
    }
}

public struct DeliveryPayload: Codable {
    public let deliveryId: String
    public let event: InAppMetric
    public let timestamp: Date
    public let metaData: [String: String]

    enum CodingKeys: String, CodingKey {
        case deliveryId = "delivery_id"
        case event
        case timestamp
        case metaData = "metadata"
    }
}

enum DeliveryType: String, Codable {
    case inApp = "in_app"
}
