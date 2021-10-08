import Foundation

/// https://customer.io/docs/api/#operation/merge
internal struct MergeCustomerRequestBody: Codable {
    let primary: String
    let secondary: String
}
