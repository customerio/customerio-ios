import Foundation

public enum Metric: String, Codable {
    case delivered
    case opened
    case converted
}

// https://customer.io/docs/api/#operation/pushMetrics
internal struct MetricRequest: Codable {
    let deliveryID: String
    let event: Metric
    let deviceToken: String
    let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case deliveryID = "delivery_id"
        case event
        case deviceToken = "device_id"
        case timestamp
    }
}
