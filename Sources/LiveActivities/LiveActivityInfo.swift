import Foundation

/// Identifies a Live Activity instance at the moment the SDK first observes it.
///
/// Emitted via `LiveActivitiesModule.observedActivities`. The host app can relay
/// this to its own backend or use it for local correlation.
public struct LiveActivityInfo {
    /// The ActivityKit-assigned activity ID (`Activity<T>.id`).
    public let activityId: String
    /// The stable reverse-DNS type identifier registered via `LiveActivityConfigBuilder.register(_:identifier:)`.
    public let activityType: String
    /// The stable per-installation UUID.
    public let installationId: String
    /// The currently identified user ID, or anonymous ID if no `identify` call has been made.
    public let userId: String
}
