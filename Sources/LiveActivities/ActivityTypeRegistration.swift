import Foundation

/// Sinks the observation bridge calls as ActivityKit emits tokens and lifecycle transitions.
///
/// The bridge only forwards raw signals; all policy (dedup, auth gating, event emission) lives
/// in `LiveActivityRegistrar` / `LiveActivityReporter`. `onActivityAppeared`/`onActivityEnded` are
/// used for token capture and cleanup only. The one lifecycle *event* observation emits is
/// `onUserDismissed` — a user's manual swipe-away — which the bridge distinguishes from an
/// app/SDK/backend-initiated end via the terminal-state path and `consumeLocalEnd`.
struct LiveActivityObservationSinks: Sendable {
    let onPushToStartToken: @Sendable (_ token: Data) -> Void
    let onInstanceToken: @Sendable (_ activityInstanceId: String, _ token: Data) -> Void
    let onActivityAppeared: @Sendable (_ activityInstanceId: String) -> Void
    let onActivityEnded: @Sendable (_ activityInstanceId: String) -> Void

    /// Called only when the user manually dismisses (swipes away) the activity — never for an
    /// app/SDK `end()` or a backend/system end. The reporter turns this into an `end` event.
    let onUserDismissed: @Sendable (_ activityInstanceId: String) -> Void

    /// Returns whether this activity was ended locally by the SDK (via `CIOLiveActivity.end`),
    /// consuming the marker. Used to suppress a spurious user-dismissal report when a local end
    /// reaches `.dismissed` without an observed `.ended` (e.g. `.immediate` dismissal policy).
    let consumeLocalEnd: @Sendable (_ activityInstanceId: String) -> Bool
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
