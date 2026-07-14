#if os(iOS)
import ActivityKit

/// A Live Activity type that declares its **own** Customer.io registration identifier, so it can be
/// registered without repeating the id:
///
/// ```swift
/// LiveActivityConfigBuilder()
///     .register(CIOSegmentsAttributes.self)   // identifier supplied by the type
///     .build()
/// ```
///
/// The built-in Customer.io templates conform. Your own `ActivityAttributes` types don't need to —
/// register those with the explicit `register(_:identifier:)`, passing the identifier the backend
/// expects.
@available(iOS 16.2, *)
public protocol CIOActivityTemplate: CIOActivityAttribute {
    /// Reverse-DNS identifier Customer.io matches server-side to route pushes for this activity type.
    static var identifier: String { get }
}
#endif
