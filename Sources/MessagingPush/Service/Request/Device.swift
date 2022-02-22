import Foundation

// Standard device structure
internal struct Device: Codable {
    let token: String
    let platform = "ios"
    let lastUsed: Date
    let attributes : [String: String]?

    enum CodingKeys: String, CodingKey {
        case platform
        case token = "id"
        case lastUsed
        case attributes
    }
}
