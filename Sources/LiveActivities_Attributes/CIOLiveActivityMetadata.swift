import Foundation

/// Customer.io delivery + routing metadata carried inside a Live Activity's `ContentState`.
///
/// Because iOS delivers Live Activity pushes straight to ActivityKit (the app never sees the raw
/// APNs payload or its headers), the Customer.io backend embeds the push's delivery identifiers
/// and tap destination *inside* the encoded `content-state`. The SDK reads them off the decoded
/// state to report `delivered`/`opened` metrics (the same pipeline normal push uses) and to set the
/// activity's tap `widgetURL`.
///
/// This is the iOS carrier for the same values Android reads from the FCM data payload
/// (`CIO-Delivery-ID` / `CIO-Delivery-Token` / deep link) — one logical contract, two transports.
///
/// Locally-started/updated activities leave this `nil`; there is no push to attribute, so no
/// delivery metric is reported.
public struct CIOLiveActivityMetadata: Codable, Hashable, Sendable {
    /// The `CIO-Delivery-ID` of the push that produced this content-state. Present ⇒ the SDK
    /// reports a `delivered` metric for it (deduped), and attributes an `opened` metric to it on tap.
    public var deliveryId: String?
    /// The `CIO-Delivery-Token` of the push, sent alongside the metric.
    public var deliveryToken: String?
    /// Optional deep link opened when the user taps the activity (backend-driven, mirrors Android's
    /// push deep link). Rendered as the activity's `widgetURL`.
    public var deepLink: String?

    public init(deliveryId: String? = nil, deliveryToken: String? = nil, deepLink: String? = nil) {
        self.deliveryId = deliveryId
        self.deliveryToken = deliveryToken
        self.deepLink = deepLink
    }
}

/// Opt-in conformance for a template's `ContentState` that carries Customer.io delivery metadata.
///
/// Built-in Customer.io templates conform so remote pushes can be attributed. Custom
/// `ActivityAttributes` types may conform to receive the same `delivered`/`opened`/deep-link
/// handling; types that don't conform simply skip metric reporting.
public protocol CIOMetadataCarrying {
    /// Delivery + routing metadata for the push that produced the current content-state, or `nil`
    /// for a locally-driven state.
    var cioMetadata: CIOLiveActivityMetadata? { get }
}
