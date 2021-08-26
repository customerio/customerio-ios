import Foundation

// Standard device structure
internal struct Device: Codable {
    let id: String
    let platform = "ios"
    let lastUsed: Date
    
    enum CodingKeys: String, CodingKey {
        case platform = "ios"
        case id
        case lastUsed
    }
}
