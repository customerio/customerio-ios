import Foundation

/// Customer.io delivery metadata that a Customer.io push attaches to a Live Activity's
/// `ContentState`.
///
/// You don't create or populate this — Customer.io sends it with a push, and the SDK reads it to
/// report `delivered`/`opened` metrics and to set the activity's tap deep link. To let Customer.io
/// attribute those for your activity, add a `cioMetadata` property to your `ContentState` by
/// conforming it to ``CIOMetadataCarrying``. It is `nil` for content-states you set locally.
public struct CIOLiveActivityMetadata: Codable, Hashable, Sendable {
    /// Delivery id of the Customer.io push that produced this content-state.
    public var deliveryId: String?
    /// Delivery token of the Customer.io push.
    public var deliveryToken: String?
    /// Deep link opened when the user taps the activity.
    public var deepLink: String?

    public init(deliveryId: String? = nil, deliveryToken: String? = nil, deepLink: String? = nil) {
        self.deliveryId = deliveryId
        self.deliveryToken = deliveryToken
        self.deepLink = deepLink
    }
}

/// Conform your `ContentState` to this and add a `cioMetadata` property to opt your Live Activity
/// into Customer.io `delivered`/`opened` metrics and tap deep links. Declare it as an optional you
/// leave `nil` — Customer.io fills it in on the content-states it delivers via push.
public protocol CIOMetadataCarrying {
    /// Customer.io delivery metadata for the current content-state; `nil` for a state you set locally.
    var cioMetadata: CIOLiveActivityMetadata? { get }
}
