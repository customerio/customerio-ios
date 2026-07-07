import CioInternalCommon
import CioLiveActivities_Attributes
import Foundation

/// Reports Live Activity push **delivery/open receipts** through the SAME pipeline normal push
/// uses — a `TrackMetricEvent` (consumed by DataPipeline → "Report Delivery Event") carrying the
/// shared `Metric.delivered` / `Metric.opened` values. One backend contract serves push, Live
/// Activities (iOS), and Live Notifications (Android).
///
/// The delivery identifiers ride inside the decoded `content-state` (`CIOLiveActivityMetadata`),
/// because iOS never exposes the raw Live Activity push to the app. `delivered` is deduped by
/// `CIO-Delivery-ID` so ActivityKit's content re-emissions and the cold-launch snapshot replay
/// can't double-report; `opened` is not deduped (each tap is a distinct open, matching push).
///
/// This type does no user gating: a delivery is a device-level receipt, reported whenever a
/// `CIO-Delivery-ID` is present (matching normal push).
final class LiveActivityDeliveryTracker: @unchecked Sendable {
    /// Posts the metric onto the shared event bus. Injected so the tracker stays decoupled from the
    /// SDK facade (mirrors `LiveActivityReporter`'s `track` closure).
    private let postMetric: @Sendable (_ deliveryId: String, _ event: String, _ deliveryToken: String) -> Void
    private let store: LiveActivityTokenStorage
    private let logger: Logger

    /// Namespace for persisted `delivered` dedup markers in the shared token store.
    static let deliveredKeyPrefix = "delivered:"

    init(
        postMetric: @escaping @Sendable (_ deliveryId: String, _ event: String, _ deliveryToken: String) -> Void,
        store: LiveActivityTokenStorage,
        logger: Logger
    ) {
        self.postMetric = postMetric
        self.store = store
        self.logger = logger
    }

    /// Reports `delivered` for the push that produced this content-state — at most once per
    /// `CIO-Delivery-ID`. No-op when the state carries no delivery id (e.g. a locally-driven state).
    func reportDelivered(metadata: CIOLiveActivityMetadata) {
        guard let deliveryId = metadata.deliveryId, !deliveryId.isEmpty else { return }
        let key = Self.deliveredKeyPrefix + deliveryId
        guard store.registrationSignature(activityType: key) == nil else { return }
        postMetric(deliveryId, Metric.delivered.rawValue, metadata.deliveryToken ?? "")
        store.setRegistrationSignature(activityType: key, signature: "1")
        logger.debug("Reported Live Activity 'delivered' deliveryId=\(deliveryId)", "LiveActivities")
    }

    /// Reports `opened` for a tapped activity. Not deduped — each tap is a distinct open.
    func reportOpened(metadata: CIOLiveActivityMetadata) {
        guard let deliveryId = metadata.deliveryId, !deliveryId.isEmpty else { return }
        postMetric(deliveryId, Metric.opened.rawValue, metadata.deliveryToken ?? "")
        logger.debug("Reported Live Activity 'opened' deliveryId=\(deliveryId)", "LiveActivities")
    }
}
