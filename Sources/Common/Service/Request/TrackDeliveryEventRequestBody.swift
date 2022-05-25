import Foundation

internal struct TrackDeliveryEventRequestBody: Codable {
    internal let type: DeliveryType
    internal let payload: DeliveryPayload
}

internal struct DeliveryPayload: Codable {
    internal let deliveryId: String
    internal let event: InAppMetric
    internal let timestamp: Date
}

internal enum DeliveryType: String, Codable {
    case inApp
}
