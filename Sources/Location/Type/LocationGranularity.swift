import Foundation

/// Semantic accuracy for location requests. Mapped internally to system accuracy settings.
public enum LocationGranularity: Equatable, Sendable {
    /// Reduced precision (e.g. city or timezone level). Never escalated to full accuracy.
    case coarseCityOrTimezone
}

/// Central default granularity for all location requests. Used by the orchestrator when calling the provider.
enum LocationGranularityDefaults {
    static let `default`: LocationGranularity = .coarseCityOrTimezone
}
