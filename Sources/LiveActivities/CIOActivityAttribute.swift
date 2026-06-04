#if os(iOS)
import ActivityKit
import Foundation

/// Extends `ActivityAttributes` with a stable, partner-supplied identity for
/// API routing.
///
/// Adopt this protocol on every `ActivityAttributes` type you register with
/// the Customer.io SDK. The `activityInstanceId` you supply is used as the
/// stable identifier in Live Activities API routes — it must be the same value
/// the server uses to target updates at this specific activity instance.
///
/// Unlike `Activity.id` (a system-assigned UUID that changes across restarts
/// and is unknown to the server), `activityInstanceId` is chosen by the app
/// and communicated to the backend at activity creation time, so both sides
/// share a consistent reference.
///
/// ```swift
/// struct OrderAttributes: CIOActivityAttribute {
///     var activityInstanceId: String   // e.g. the order number
///     var branding: CIOActivityBranding
///     struct ContentState: Codable, Hashable { … }
/// }
/// ```
@available(iOS 17.2, *)
public protocol CIOActivityAttribute: ActivityAttributes {
    /// A stable, partner-supplied identifier for this activity instance.
    ///
    /// Used in API paths and matched server-side to route push updates to the
    /// correct activity. Must be unique per activity instance and consistent
    /// between the app and the Customer.io backend.
    var activityInstanceId: String { get }
}
#endif
