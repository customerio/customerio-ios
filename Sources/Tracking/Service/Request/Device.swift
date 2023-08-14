import Foundation

// Standard device structure
struct Device<T: Encodable>: Encodable {
    let token: String
    let platform: String // iOS, tvOS, watchOS, etc.
    let lastUsed: Date
    let attributes: T?

    enum CodingKeys: String, CodingKey {
        case platform
        case token = "id"
        case lastUsed = "last_used"
        case attributes
    }
}
