import CioInternalCommon
import CioLiveActivities_Attributes
import Foundation

#if os(iOS)
import ActivityKit

/// A handle to a Live Activity the SDK is managing locally.
///
/// Returned by `CustomerIO.liveActivities.start(...)` and `adopt(_:)`. Starting and ending the
/// activity through this handle is what emits the local `start`/`end` `Live Notification Event`s. A
/// local `update` is applied to the activity but is intentionally not reported — only `start`/`end`
/// emit a CDP event. A backend push that changes or ends the activity is applied by the OS and is
/// never reported either.
///
/// > Important: Ending the underlying `activity` directly (bypassing this handle) performs the
/// > ActivityKit operation but emits no Customer.io event.
@available(iOS 16.2, *)
public struct CIOLiveActivity<Attributes: ActivityAttributes> {
    /// The stable correlation id (minted by the SDK for local starts, or carried in the
    /// attributes for push-to-start), reported to the backend as `instanceUUID`.
    public let id: String

    /// The underlying ActivityKit activity, if you need direct access.
    public let activity: Activity<Attributes>

    private let reporter: LiveActivityReporter
    private let notificationType: String
    private let logger: Logger

    /// Marks this activity as an SDK-initiated end so observation doesn't misread the resulting
    /// terminal state as a user dismissal and double-report.
    private let markLocalEnd: @Sendable (String) -> Void

    init(
        id: String,
        activity: Activity<Attributes>,
        reporter: LiveActivityReporter,
        notificationType: String,
        logger: Logger,
        markLocalEnd: @escaping @Sendable (String) -> Void
    ) {
        self.id = id
        self.activity = activity
        self.reporter = reporter
        self.notificationType = notificationType
        self.logger = logger
        self.markLocalEnd = markLocalEnd
    }

    /// Apply a local content-state update to the activity.
    ///
    /// The new content-state is applied locally via ActivityKit. This is intentionally **not**
    /// reported to Customer.io — only `start` and `end` emit a `Live Notification Event`.
    public func update(
        _ contentState: Attributes.ContentState,
        staleDate: Date? = nil,
        alert: AlertConfiguration? = nil
    ) async {
        await activity.update(ActivityContent(state: contentState, staleDate: staleDate), alertConfiguration: alert)
    }

    /// End the activity locally and report an `end` event with an optional final content-state.
    public func end(
        _ finalContentState: Attributes.ContentState? = nil,
        dismissalPolicy: ActivityUIDismissalPolicy = .default
    ) async {
        // Mark before ending so the marker is set before ActivityKit emits any terminal state to
        // the observer, avoiding a race where `.dismissed` arrives first.
        markLocalEnd(id)
        if let finalContentState {
            await activity.end(ActivityContent(state: finalContentState, staleDate: nil), dismissalPolicy: dismissalPolicy)
        } else {
            await activity.end(nil, dismissalPolicy: dismissalPolicy)
        }
        reporter.reportEnd(
            instanceUUID: id,
            notificationType: notificationType,
            contentState: finalContentState.flatMap(LiveActivityReporter.encode)
        )
    }
}
#endif
