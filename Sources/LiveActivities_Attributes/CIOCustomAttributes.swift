#if os(iOS)
import ActivityKit
import Foundation

/// A ready-made `ActivityAttributes` type whose content is an untyped map, for Live Activities
/// whose shape isn't known at compile time.
///
/// ActivityKit needs a concrete Swift type to register an activity, observe its push-to-start
/// token, and decode a pushed content-state. That is impossible to supply from a cross-platform
/// runtime — a React Native or Flutter app cannot hand the SDK a Swift metatype — so Customer.io
/// owns this type on their behalf and carries their values in ``ContentState/data``.
///
/// Register it under your own identifier, then render it in your Widget Extension:
///
/// ```swift
/// let config = SDKConfigBuilder(cdpApiKey: "your_key")
///     .addModule(LiveActivitiesModule(config:
///         LiveActivityConfigBuilder()
///             .register(CIOCustomAttributes.self, identifier: "com.myapp.rideshare")
///             .build()))
///     .build()
/// ```
///
/// ```swift
/// ActivityConfiguration(for: CIOCustomAttributes.self) { context in
///     Text(context.state.data["status"] ?? "")
/// } dynamicIsland: { context in
///     // ...
/// }
/// ```
///
/// > Important: an activity's reported type is resolved from its attributes type, so registering
/// > this one type under two identifiers would make every event resolve to whichever was
/// > registered first. Register it once. Define your own `ActivityAttributes` type when you need
/// > several distinct activities — that is the better option whenever you can write Swift.
@available(iOS 16.2, *)
public struct CIOCustomAttributes: CIOActivityAttribute {
    /// Correlation id managed by Customer.io — don't set or read it yourself.
    public var cioInstanceId: String = ""

    public struct ContentState: Codable, Hashable, CIOMetadataCarrying {
        /// The values that drive your widget. Everything is a string because there is no schema to
        /// decode against: the content arrives either from a cross-platform bridge or from a push
        /// payload, and neither tells the SDK what types to expect. Parse what you need at render
        /// time.
        public var data: [String: String]

        /// Delivery metadata Customer.io fills in on pushed content-states, used to report
        /// `delivered` and to resolve a tap's destination. Leave it `nil` when you update locally.
        public var cioMetadata: CIOLiveActivityMetadata?

        public init(data: [String: String], cioMetadata: CIOLiveActivityMetadata? = nil) {
            self.data = data
            self.cioMetadata = cioMetadata
        }
    }

    public init() {}
}
#endif
