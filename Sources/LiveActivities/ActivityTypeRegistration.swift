import CioLiveActivities_Attributes
import Foundation

/// Sinks the observation bridge calls as ActivityKit emits tokens and lifecycle transitions.
///
/// The bridge only forwards raw signals; all policy (dedup, auth gating, event emission) lives
/// in `LiveActivityRegistrar` / `LiveActivityReporter`. `onActivityEnded` is used for cleanup
/// only. The one lifecycle *event* observation emits is `onUserDismissed` — a user's manual
/// swipe-away — which the bridge distinguishes from an app/SDK/backend-initiated end via the
/// terminal-state path and `consumeLocalEnd`.
struct LiveActivityObservationSinks: Sendable {
    let onPushToStartToken: @Sendable (_ token: Data) -> Void
    let onInstanceToken: @Sendable (_ cioInstanceId: String, _ token: Data) -> Void
    let onActivityEnded: @Sendable (_ cioInstanceId: String) -> Void

    /// Called only when the user manually dismisses (swipes away) the activity — never for an
    /// app/SDK `end()` or a backend/system end. The reporter turns this into an `end` event.
    let onUserDismissed: @Sendable (_ cioInstanceId: String) -> Void

    /// Called with the Customer.io delivery metadata carried in a content-state — on first
    /// observation (the start push's state) and on every subsequent push update. Used to report
    /// `delivered` receipts and to record the current tap destination for `opened` tracking.
    /// Not called for content-states without metadata (e.g. locally-driven updates).
    let onContentMetadata: @Sendable (_ cioInstanceId: String, _ metadata: CIOLiveActivityMetadata) -> Void

    /// Returns whether this activity was ended locally by the SDK (via `CIOLiveActivity.end`),
    /// consuming the marker. Used to suppress a spurious user-dismissal report when a local end
    /// reaches `.dismissed` without an observed `.ended` (e.g. `.immediate` dismissal policy).
    let consumeLocalEnd: @Sendable (_ cioInstanceId: String) -> Bool

    /// Resolves the stable CIO instance id for an observed activity, given the system `Activity.id`
    /// and the id read from the activity's attributes (`cioInstanceId`) when the type conforms to
    /// `CIOActivityAttribute`, or `nil` for a plain `ActivityAttributes` type. Backed by the token
    /// store's persisted map so a locally-started activity keeps its minted id across relaunch.
    let resolveInstanceId: @Sendable (_ activityId: String, _ attributesInstanceId: String?) -> String

    /// Drops the `Activity.id` → instance id mapping when the activity reaches a terminal state.
    let clearInstanceIdMapping: @Sendable (_ activityId: String) -> Void
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

    /// Ends all currently-running activities of this type immediately (used on reset). Each running
    /// activity is passed to `prepareLocalEnd` (its system `activityId` + attributes instance id, if
    /// the type carries one) *before* it is ended, so the caller can mark it as an SDK-initiated end.
    /// The `.immediate` dismissal surfaces as a `.dismissed` terminal, which must not be reported as
    /// a user swipe.
    let endAllActivities: @Sendable (_ prepareLocalEnd: @Sendable (_ activityId: String, _ attributesInstanceId: String?) -> Void) async -> Void
}
