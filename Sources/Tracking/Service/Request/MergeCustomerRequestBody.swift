import Foundation

/// https://customer.io/docs/api/#operation/identify
internal struct MergeCustomerRequestBody: Codable {
    let primary: String
    let secondary: String
}
