import Foundation

/// Sinks the observation bridge calls as ActivityKit emits tokens and lifecycle transitions.
///
/// The bridge only forwards raw signals; all policy (dedup, auth gating, event emission) lives
/// in `LiveActivityRegistrar` / `LiveActivityReporter`. No lifecycle *events* are emitted from
/// observation — `onActivityAppeared`/`onActivityEnded` are used for token capture and cleanup only.
struct LiveActivityObservationSinks: Sendable {
    let onPushToStartToken: @Sendable (_ token: Data) -> Void
    let onInstanceToken: @Sendable (_ activityInstanceId: String, _ token: Data) -> Void
    let onActivityAppeared: @Sendable (_ activityInstanceId: String) -> Void
    let onActivityEnded: @Sendable (_ activityInstanceId: String) -> Void
}

/// Type-erased descriptor for a single registered `ActivityAttributes` type.
///
/// Created by `LiveActivityConfigBuilder.register(_:identifier:)` (which delegates to
/// `LiveActivityObservation`) and stored as pure data in `LiveActivityConfig`. All generic
/// `Activity<T>` interaction is captured inside `startObserving`, so this type carries no
/// `@available` restriction and the config stays free of observation logic.
struct ActivityTypeRegistration: Sendable {
    /// The reverse-DNS `notificationType` for this activity type (used in events and API routing).
    let activityIdentifier: String

    /// The Swift `ActivityAttributes` type name (`String(describing: T.self)`), sent to the
    /// backend as the APNs `attributes-type` so it can build push-to-start payloads.
    let attributesTypeName: String

    /// Bridges this type's ActivityKit streams into `sinks`. Returns the root observation task;
    /// cancelling it stops all observation for this type.
    let startObserving: @Sendable (_ sinks: LiveActivityObservationSinks) -> Task<Void, Never>

    /// Ends all currently-running activities of this type immediately (used on reset).
    let endAllActivities: @Sendable () async -> Void
}
