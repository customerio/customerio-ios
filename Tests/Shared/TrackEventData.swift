@testable import CioTracking
import Foundation

/// Example event body
public struct TrackEventData: Codable, Equatable {
    var product: String?
    var count: Int?
    var price: Int?
}

public extension TrackEventData {
    static func random(update: Bool = false) -> TrackEventData {
        TrackEventData(
            product: String.random,
            count: Int.random(in: 1 ... 10),
            price: Int.random(in: 10 ... 100)
        )
    }

    static func blank() -> TrackEventData {
        TrackEventData(product: nil, count: nil, price: nil)
    }
}

public struct TrackRequestDecodable: Decodable {
    public let name: String
    public let data: TrackEventData
    public let timestamp: Date?
}
