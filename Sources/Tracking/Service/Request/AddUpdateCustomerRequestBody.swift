import Foundation

/// https://customer.io/docs/api/#operation/identify
internal struct AddUpdateCustomerRequestBody: Codable {
    let email: String?
    let anonymousId: String?
}
