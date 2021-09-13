import Foundation

/// https://customer.io/docs/api/#operation/track
internal struct TrackRequestBody: Encodable {
    let name: String
    let data: Encodable
    let timestamp: Date? = nil
    
    enum CodingKeys: String, CodingKey {
        case name
        case data
        case timestamp
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(data, forKey: .data)
        if self.timestamp != nil {
            try container.encode(timestamp, forKey: .timestamp)
        }
    }
}
