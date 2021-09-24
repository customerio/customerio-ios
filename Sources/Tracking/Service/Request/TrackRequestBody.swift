import Foundation

/// https://customer.io/docs/api/#operation/track
internal struct TrackRequestBody<T: Encodable>: Encodable {
    let name: String
    let data: T?
    let timestamp: Date?
    let type: String? // if using page views, use "page"
}
