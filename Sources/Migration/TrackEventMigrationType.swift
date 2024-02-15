import Foundation

enum EventType: String, Codable {
    case event
    case screen
}

public struct TrackEventTypeForAnalytics: Codable {
    let type: EventType
    let name: String
    let timestamp: Date?
}
