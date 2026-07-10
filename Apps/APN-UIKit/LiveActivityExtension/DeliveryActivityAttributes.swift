#if os(iOS)
import ActivityKit
import CioLiveActivities_Attributes
import Foundation

/// Example `ActivityAttributes` for a delivery-tracking Live Activity.
///
/// This is the reference for how a Customer.io customer models their own Live Activity: you own
/// the attributes type and the widget that renders it; the SDK handles registration, push tokens,
/// lifecycle reporting, and (for push-to-start) remote creation.
///
/// The file is a member of **both** the app target (which starts/updates the activity via the SDK)
/// and the widget extension target (which renders it). ActivityKit matches the two sides by the
/// attributes type *name* and its `Codable` shape — not by type identity — so sharing one source
/// file across both targets is the intended pattern.
///
/// Conforming to `CIOActivityAttribute` (a one-property protocol adding `cioInstanceId`) opts this
/// type into **push-to-start**: the backend can create the activity remotely and the SDK/backend
/// populate `cioInstanceId` for you. A custom type does *not* have to conform — a plain
/// `ActivityAttributes` works for local `start`/`update`/`end` and instance-token pushes; conform
/// only when you want remote start.
@available(iOS 16.2, *)
struct DeliveryActivityAttributes: CIOActivityAttribute {
    /// Reverse-DNS identifier registered with the SDK and matched server-side to route pushes.
    static let identifier = "io.customer.liveactivities.deliverytracking"

    /// SDK/backend-managed correlation id. Declared with a default and never set by you — the SDK
    /// fills it in on local `start`, the backend fills it in for push-to-start.
    var cioInstanceId: String = ""

    /// Static order label, set once at start and rendered verbatim; never changes for the activity.
    var orderNumber: String

    init(orderNumber: String) {
        self.orderNumber = orderNumber
    }

    /// Step-based delivery progress (e.g. 2 of 4).
    struct Progress: Codable, Hashable, Sendable {
        /// Current step (1-based).
        var current: Int
        /// Total number of steps.
        var total: Int

        init(current: Int, total: Int) {
            self.current = current
            self.total = total
        }

        /// Fraction complete in `0...1`, clamped so a malformed push can't produce an invalid bar.
        var fraction: Double {
            guard total > 0 else { return 0 }
            return min(max(Double(current) / Double(total), 0), 1)
        }
    }

    /// The dynamic part of the activity — everything that changes as the delivery progresses.
    struct ContentState: Codable, Hashable, Sendable, CIOMetadataCarrying {
        /// Primary status line, e.g. `"Out for delivery"`. Rendered verbatim.
        var title: String
        /// Optional secondary line, e.g. `"Arriving at 1:30 PM"`. Rendered verbatim.
        var subtitle: String?
        /// Step-based delivery progress.
        var progress: Progress
        /// Estimated arrival, used to render a live countdown. Epoch **seconds** on the wire — the
        /// Customer.io backend sends all date fields in seconds; `EpochSecondsDate` decodes them.
        var estimatedArrival: EpochSecondsDate?
        /// Optional hex accent color (e.g. `"#34C759"`) for the status. `nil` uses the default tint.
        var statusColor: String?
        /// Customer.io delivery + deep-link metadata for the push that produced this state.
        /// `nil` for a locally-driven update (no push to attribute).
        var cioMetadata: CIOLiveActivityMetadata?

        init(
            title: String,
            subtitle: String? = nil,
            progress: Progress,
            estimatedArrival: EpochSecondsDate? = nil,
            statusColor: String? = nil,
            cioMetadata: CIOLiveActivityMetadata? = nil
        ) {
            self.title = title
            self.subtitle = subtitle
            self.progress = progress
            self.estimatedArrival = estimatedArrival
            self.statusColor = statusColor
            self.cioMetadata = cioMetadata
        }
    }
}
#endif
