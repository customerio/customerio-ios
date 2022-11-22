import Common
import Foundation

// https://customer.io/docs/api/#operation/pushMetrics
internal struct MetricRequest: Codable {
    let deliveryId: String
    let event: Metric
    let deviceToken: String
    let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case deliveryId
        case event
        case deviceToken = "deviceId"
        case timestamp
    }
}

internal extension MetricRequest {
    static var random: MetricRequest {
        MetricRequest(deliveryId: String.random, event: .opened, deviceToken: String.random, timestamp: Date())
    }
}
