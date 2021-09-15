import Foundation

/// https://customer.io/docs/api/#operation/track
internal struct TrackRequestBody<T: Encodable>: Encodable {
    let name: String
    let data: T?
    let timestamp: Date?

    enum CodingKeys: String, CodingKey {
        case name
        case data
        case timestamp
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        if data != nil, !(data is EmptyRequestBody) {
            try container.encode(data, forKey: .data)
        }
        if timestamp != nil {
            try container.encode(timestamp, forKey: .timestamp)
        }
    }
}
