import CoreLocation
import Foundation

/// Forwards CLLocationManagerDelegate callbacks into the CoreLocationProvider actor.
/// Not MainActor-isolated so the protocol conformance does not cross isolation in Swift 6.
/// Delegate methods are lightweight and forward via Task { await provider?... }.
/// One-shot only: didUpdateLocations and didFailWithError.
final class CoreLocationProviderDelegateProxy: NSObject, CLLocationManagerDelegate {
    private weak var provider: CoreLocationProvider?

    override init() {
        super.init()
    }

    /// Set after the provider is created so the proxy can forward delegate callbacks.
    func setProvider(_ provider: CoreLocationProvider) {
        self.provider = provider
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { await provider?.didUpdateLocations([location]) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { await provider?.didFailWithError(error) }
    }
}
