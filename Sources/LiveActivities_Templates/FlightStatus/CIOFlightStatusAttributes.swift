import CioLiveActivities_Attributes
import Foundation

#if os(iOS)
import ActivityKit

/// Attributes for the Flight Status template.
///
/// Tracks a single flight from departure through arrival with real-time
/// gate, terminal, delay, and in-flight progress updates.
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
    public var branding: CIOActivityBranding
    /// Flight number e.g. `"AA1234"`.
    public var flightNumber: String
    public var origin: Airport
    public var destination: Airport

    public init(
        activityInstanceId: String,
        branding: CIOActivityBranding,
        flightNumber: String,
        origin: Airport,
        destination: Airport
    ) {
        self.activityInstanceId = activityInstanceId
        self.branding = branding
        self.flightNumber = flightNumber
        self.origin = origin
        self.destination = destination
    }

    // MARK: - Dynamic content state

    public struct ContentState: Codable, Hashable, Sendable {
        /// Human-readable status e.g. `"On time"`, `"Delayed 45 min"`, `"Boarding now"`.
        public var statusMessage: String
        /// Gate identifier. `nil` when not yet assigned.
        public var gate: String?
        /// Terminal identifier. `nil` when not yet assigned.
        public var terminal: String?
        public var scheduledDeparture: Date
        public var estimatedArrival: Date
        /// In-flight progress fraction 0.0–1.0. `nil` before departure.
        public var progressFraction: Double?
        /// Positive delay in minutes. `nil` when on time.
        public var delayMinutes: Int?
        /// Message shown when the activity becomes stale.
        public var staleMessage: String?

        public init(
            statusMessage: String,
            gate: String? = nil,
            terminal: String? = nil,
            scheduledDeparture: Date,
            estimatedArrival: Date,
            progressFraction: Double? = nil,
            delayMinutes: Int? = nil,
            staleMessage: String? = nil
        ) {
            self.statusMessage = statusMessage
            self.gate = gate
            self.terminal = terminal
            self.scheduledDeparture = scheduledDeparture
            self.estimatedArrival = estimatedArrival
            self.progressFraction = progressFraction
            self.delayMinutes = delayMinutes
            self.staleMessage = staleMessage
        }
    }
}
#endif
