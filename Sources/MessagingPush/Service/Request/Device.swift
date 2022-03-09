import Foundation

// Standard device structure
internal struct Device<T: Encodable>: Encodable {
    let token: String
    let platform = "ios"
    let lastUsed: Date
    let attributes: T?

    enum CodingKeys: String, CodingKey {
        case platform
        case token = "id"
        case lastUsed
        case attributes
    }
}
