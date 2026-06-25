import Foundation

/// Type-erased registration for a single `ActivityAttributes` conformance.
///
/// Created by `LiveActivityConfigBuilder.register(_:identifier:)` and stored in
/// `LiveActivityConfig.registrations`. `LiveActivitiesModule` iterates
/// registrations during initialization and starts an observation task for each.
///
/// All ActivityKit interaction is encapsulated inside the stored closures, so
/// this type carries no `@available` restriction and can be stored without
/// conditional compilation.
struct ActivityTypeRegistration {
    /// The canonical identifier for this activity type.
    ///
    /// Used in API paths and as the key for the observation task registry.
    /// Should be a stable reverse-DNS string such as
    /// `"io.customer.liveactivities.scoreboard"`.
    let activityIdentifier: String

    /// Starts monitoring all live activities of the registered type.
    ///
    /// The returned `Task` runs until cancelled; cancelling it stops all
    /// observation for this activity type.
    ///
    /// - Parameters:
    ///   - onPushToStartToken: Invoked with the current push-to-start token
    ///     and again whenever the system rotates it.
    ///   - onInstancePushToken: Invoked with `(activityId, tokenData)` when an
    ///     activity becomes active and again on token rotation. The backend uses
    ///     this token to deliver APNs content-state updates to the instance.
    ///   - onActivityObserved: Invoked once per activity with its `activityId`,
    ///     the JSON-encoded initial content state (if encodable), and the
    ///     activity's stale date (if set by the host app) when first seen.
    ///   - onStateUpdate: Invoked with `(activityId, contentStateJSON)` whenever
    ///     an active activity's content state changes.
    ///   - onEnd: Invoked with the `activityId` and JSON-encoded final content
    ///     state (if available) when an activity ends or is dismissed.
    let startObserving:
        (
            _ onPushToStartToken: @escaping (Data) async -> Void,
            _ onInstancePushToken: @escaping (String, Data) async -> Void,
            _ onActivityObserved: @escaping (String, Data?, Date?) async -> Void,
            _ onStateUpdate: @escaping (String, Data) async -> Void,
            _ onEnd: @escaping (String, Data?) async -> Void
        ) -> Task<Void, Never>

    /// Ends all currently-running activities of the registered type immediately.
    ///
    /// Called on reset events to clear orphaned activities before the module
    /// tears down its observation tasks.
    let endAllActivities: () async -> Void
}
