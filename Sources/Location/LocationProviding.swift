import CioInternalCommon
import Foundation

/// Abstracts system location. One-shot only; no permission request APIs.
/// Implementations (e.g. an actor wrapping CLLocationManager) are thread-safe via actor isolation.
///
/// This component does not request location permission. The host app must prompt for authorization
/// (e.g. via `CLLocationManager.requestWhenInUseAuthorization()`) and only call location APIs once authorized.
///
/// Not AutoMockable: protocol uses async methods; Sourcery generates sync mocks. Use MockLocationProvider in tests.
protocol LocationProviding: Sendable {
    /// One-shot location request. Returns `nil` if a request is already in flight (call ignored).
    /// Does not request permission; caller must ensure authorization before calling.
    func requestLocationOnce() async -> LocationResult?

    /// Cancels any in-flight one-shot request. Idempotent.
    func cancel() async
}
