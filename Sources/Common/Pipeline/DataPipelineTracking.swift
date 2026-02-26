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
    /// Current identified user id, or nil if anonymous / not identified.
    var userId: String? { get }

    /// Sends a track event with the given name and properties.
    func track(name: String, properties: [String: Any])
}
