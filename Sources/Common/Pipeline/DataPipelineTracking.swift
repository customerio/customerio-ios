import Foundation

/// Abstraction for sending track events to the data pipeline.
///
/// Modules resolve an implementation via `DIGraphShared.getOptional(DataPipelineTracking.self)`
/// to send events directly when the DataPipelines module is present.
/// When no implementation is registered (e.g. DataPipelines not initialized), resolution returns nil
/// and the caller no-ops for track when no implementation is registered.
///
/// Internal SDK contract — not intended for use by host app developers.
public protocol DataPipelineTracking: AnyObject {
    /// True when a user is currently identified (non-anonymous); false when anonymous or after clearIdentify.
    var isUserIdentified: Bool { get }

    /// Sends a track event with the given name and properties.
    func track(name: String, properties: [String: Any])
}
