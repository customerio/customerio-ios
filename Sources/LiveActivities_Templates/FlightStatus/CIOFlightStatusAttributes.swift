import CioLiveActivities_Attributes
import Foundation

#if os(iOS)
import ActivityKit

/// Attributes for the Flight Status template.
///
/// Tracks a single flight from departure through arrival with real-time
/// status, progress, and freeform detail lines.
///
/// Text fields (`header`, `status`, `title`, `subtitle`) are freeform slots rendered
/// verbatim; the SDK never composes them.
@available(iOS 17.2, *)
public struct CIOFlightStatusAttributes: CIOActivityAttribute {
    public static let identifier = "io.customer.liveactivities.flightstatus"

    // MARK: - Nested types

    public struct Airport: Codable, Hashable, Sendable {
        /// IATA airport code e.g. `"SFO"`.
        public var code: String
        /// City name e.g. `"San Francisco"`.
        public var city: String

        public init(code: String, city: String) {
            self.code = code
            self.city = city
        }
    }

    // MARK: - Static attributes

    public var activityInstanceId: String
    /// Optional top line, e.g. flight number or airline. Rendered verbatim.
    public var header: String?
    public var origin: Airport
    public var destination: Airport

    public init(
        activityInstanceId: String,
        header: String? = nil,
        origin: Airport,
        destination: Airport
    ) {
        self.activityInstanceId = activityInstanceId
        self.header = header
        self.origin = origin
        self.destination = destination
    }

    // MARK: - Dynamic content state

    public struct ContentState: Codable, Hashable, Sendable {
        /// Optional short status label, e.g. `"On time"`, `"Delayed"`, `"Boarding"`. Rendered verbatim.
        public var status: String?
        /// Primary contextual line. Rendered verbatim.
        public var title: String
        /// Optional secondary line, e.g. gate / terminal / zone / bag. Rendered verbatim.
        public var subtitle: String?
        public var scheduledDeparture: EpochMillisDate
        public var estimatedArrival: EpochMillisDate
        /// In-flight progress fraction 0.0–1.0. `nil` before departure.
        public var progressFraction: Double?
        /// Hex color (e.g. `"#34C759"`) applied to status accents. `nil` uses the template tint.
        public var statusColor: String?
        /// Message shown when the activity becomes stale.
        public var staleMessage: String?

        public init(
            status: String? = nil,
            title: String,
            subtitle: String? = nil,
            scheduledDeparture: EpochMillisDate,
            estimatedArrival: EpochMillisDate,
            progressFraction: Double? = nil,
            statusColor: String? = nil,
            staleMessage: String? = nil
        ) {
            self.status = status
            self.title = title
            self.subtitle = subtitle
            self.scheduledDeparture = scheduledDeparture
            self.estimatedArrival = estimatedArrival
            self.progressFraction = progressFraction
            self.statusColor = statusColor
            self.staleMessage = staleMessage
        }
    }
}
#endif
