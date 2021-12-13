import Foundation

/// https://customer.io/docs/api/#operation/track
internal struct TrackRequestBody<T: Encodable>: Encodable {
    let type: EventType
    let name: String
    let data: T?
    let timestamp: Date?
}

public enum EventType: String, Codable {
    case event
    case screen
    
    enum CodingKeys: String, CodingKey {
        case event
        case screen
    }
}
