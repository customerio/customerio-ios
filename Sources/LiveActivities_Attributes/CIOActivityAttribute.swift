#if os(iOS)
import ActivityKit
import Foundation

/// Conform your `ActivityAttributes` type to this protocol to let Customer.io **start Live
/// Activities remotely** (push-to-start).
///
/// To adopt it, add a `cioInstanceId` property declared as a `var` with a default value and
/// leave it out of your initializer — Customer.io manages that value for you, so never set or
/// read it yourself:
///
/// ```swift
/// struct OrderAttributes: CIOActivityAttribute {
///     var cioInstanceId: String = ""   // managed by Customer.io — leave defaulted
///     var orderNumber: String
///     struct ContentState: Codable, Hashable { /* ... */ }
/// }
/// ```
///
/// Conforming is only required for push-to-start. If you only start activities locally, a plain
/// `ActivityAttributes` type works everywhere else — local `start`/`adopt`, push updates to a
/// running activity, and relaunch recovery.
@available(iOS 16.2, *)
public protocol CIOActivityAttribute: ActivityAttributes {
    /// Correlation id managed by Customer.io. Declare it as a `var` with a default value
    /// (e.g. `= ""`) and don't set or read it yourself — Customer.io assigns it.
    var cioInstanceId: String { get set }
}
#endif
