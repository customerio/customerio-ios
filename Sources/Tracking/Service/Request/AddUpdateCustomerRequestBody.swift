import Foundation

internal struct AddUpdateCustomerRequestBody: Codable {
    let email: String?
    let anonymousId: String?
    let createdAt: Date?
}
