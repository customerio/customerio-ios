import Foundation

// Standard device structure
internal struct Device: Codable {
    let token: Data
    let platform = "ios"
    let lastUsed: Date
    
    enum CodingKeys: String, CodingKey {
        case platform
        case token = "id"
        case lastUsed
    }
}
