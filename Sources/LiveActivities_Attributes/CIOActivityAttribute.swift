#if os(iOS)
import ActivityKit
import Foundation

/// Extends `ActivityAttributes` with an SDK-managed correlation id, enabling
/// **push-to-start** for the conforming activity type.
///
/// Conform your `ActivityAttributes` type to this protocol only when you want the
/// Customer.io backend to be able to *start* activities remotely. For that case the
/// backend stamps `cioInstanceId` into the attributes it creates on-device, so the SDK
/// can correlate the resulting activity with the server-side instance.
///
/// You never populate `cioInstanceId` yourself: declare it with a default (`= ""`) and
/// omit it from your initializer. The SDK fills it in on local `start`, and the backend
/// fills it in for push-to-start.
///
/// A plain `ActivityAttributes` type (not conforming to this protocol) is fully supported
/// for local `start`/`adopt`, instance-token push updates, and relaunch recovery —
/// everything except push-to-start.
///
/// ```swift
/// struct OrderAttributes: CIOActivityAttribute {
///     var cioInstanceId: String = ""   // SDK/backend-managed; leave defaulted
///     var orderNumber: String
///     struct ContentState: Codable, Hashable { … }
/// }
/// ```
@available(iOS 16.2, *)
public protocol CIOActivityAttribute: ActivityAttributes {
    /// SDK-managed correlation id for this activity instance.
    ///
    /// Populated by the SDK (local start) or the Customer.io backend (push-to-start) and
    /// matched server-side to route push updates to the correct activity. Declare it with a
    /// default value and never set it yourself.
    var cioInstanceId: String { get }
}
#endif
