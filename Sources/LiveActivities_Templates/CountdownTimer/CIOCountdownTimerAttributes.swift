import CioLiveActivities_Attributes
import Foundation

#if os(iOS)
import ActivityKit

/// Attributes for the Countdown Timer template.
///
/// Displays a live countdown to a target date with an image and configurable
/// messaging. Supports a post-expiry state via `expiredMessage`.
///
/// Text fields (`header`, `title`, `subtitle`, `expiredMessage`) are freeform slots rendered
/// verbatim; the SDK never composes them.
@available(iOS 17.2, *)
public struct CIOCountdownTimerAttributes: CIOActivityAttribute {
    public static let identifier = "io.customer.liveactivities.countdowntimer"

    // MARK: - Static attributes

    public var activityInstanceId: String
    /// Optional top line, e.g. a brand label. Rendered verbatim.
    public var header: String?
    /// Primary title displayed above the countdown e.g. `"Flash Sale"`. Rendered verbatim.
    public var title: String
    /// Asset reference for an image (bundle name / asset key / URL), resolved via `CIOAssetLibrary`.
    public var image: String?

    public init(
        activityInstanceId: String,
        header: String? = nil,
        title: String,
        image: String? = nil
    ) {
        self.activityInstanceId = activityInstanceId
        self.header = header
        self.title = title
        self.image = image
    }

    // MARK: - Dynamic content state

    public struct ContentState: Codable, Hashable, Sendable {
        /// The countdown target. Dynamic so the deadline can be extended via push.
        public var targetDate: EpochMillisDate
        /// Label displayed above the timer e.g. `"Sale ends in"`. Rendered verbatim.
        public var subtitle: String
        /// Replaces the countdown once `targetDate` has passed e.g. `"Sale is live!"`.
        /// `nil` hides the activity post-expiry. Rendered verbatim.
        public var expiredMessage: String?
        /// Hex color (e.g. `"#34C759"`) applied to accents. `nil` uses the template tint.
        public var statusColor: String?
        /// Message shown when the activity becomes stale.
        public var staleMessage: String?

        public init(
            targetDate: EpochMillisDate,
            subtitle: String,
            expiredMessage: String? = nil,
            statusColor: String? = nil,
            staleMessage: String? = nil
        ) {
            self.targetDate = targetDate
            self.subtitle = subtitle
            self.expiredMessage = expiredMessage
            self.statusColor = statusColor
            self.staleMessage = staleMessage
        }
    }
}
#endif
