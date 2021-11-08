import Foundation

/// https://customer.io/docs/api/#operation/track
internal struct TrackRequestBody<T: Encodable>: Encodable {
    let name: String
    let data: T?
    let timestamp: Date?

    /// provide keys because we allow customer to set custom JSONEncoder and we want to enforce that the keys
    /// are what the Customer.io API expects. the custom JSONEncoder will be used for `data` encoding.
    private enum CodingKeys: String, CodingKey {
        case name
        case data
        case timestamp
    }
}
