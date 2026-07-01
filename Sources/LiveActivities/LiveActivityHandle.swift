import CioLiveActivities_Attributes
import Foundation

#if os(iOS)
import ActivityKit

/// A handle to a Live Activity the SDK is managing locally.
///
/// Returned by `LiveActivitiesModule.start(...)` and `adopt(_:)`. Driving the activity through
/// this handle's `update`/`end` is what emits the local `Live Notification Event`s — a backend
/// push that changes or ends the activity is applied by the OS and is never reported.
///
/// > Important: Ending or updating the underlying `activity` directly (bypassing this handle)
/// > performs the ActivityKit operation but emits no Customer.io event.
@available(iOS 17.2, *)
public struct CIOLiveActivity<Attributes: CIOActivityAttribute> {
    /// The stable correlation id (minted by the SDK for local starts, or carried in the
    /// attributes for push-to-start), reported to the backend as `instanceUUID`.
    public let id: String

    /// The underlying ActivityKit activity, if you need direct access.
    public let activity: Activity<Attributes>

    private let reporter: LiveActivityReporter
    private let notificationType: String

    init(id: String, activity: Activity<Attributes>, reporter: LiveActivityReporter, notificationType: String) {
        self.id = id
        self.activity = activity
        self.reporter = reporter
        self.notificationType = notificationType
    }

    /// Apply a local content-state update and report an `update` event.
    public func update(
        _ contentState: Attributes.ContentState,
        staleDate: Date? = nil,
        alert: AlertConfiguration? = nil
    ) async {
        await activity.update(ActivityContent(state: contentState, staleDate: staleDate), alertConfiguration: alert)
        reporter.reportUpdate(
            instanceUUID: id,
            notificationType: notificationType,
            payload: LiveActivityReporter.payload(from: contentState)
        )
    }

    /// End the activity locally and report an `end` event.
    public func end(
        _ finalContentState: Attributes.ContentState? = nil,
        dismissalPolicy: ActivityUIDismissalPolicy = .default
    ) async {
        if let finalContentState {
            await activity.end(ActivityContent(state: finalContentState, staleDate: nil), dismissalPolicy: dismissalPolicy)
        } else {
            await activity.end(nil, dismissalPolicy: dismissalPolicy)
        }
        reporter.reportEnd(instanceUUID: id, notificationType: notificationType)
    }
}
#endif
