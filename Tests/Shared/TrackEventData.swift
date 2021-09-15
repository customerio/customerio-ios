@testable import CioTracking
import Foundation

/// Example request body object for identifying customer
public struct TrackEventData: Codable, Equatable {
    var product: String
    var count: Int
    var price: Int
}

public extension TrackEventData {
    static func random(update: Bool = false) -> TrackEventData {
        TrackEventData(product: String.random,
                       count: Int.random(in: 1 ... 10),
                       price: Int.random(in: 10 ... 100))
    }
}
