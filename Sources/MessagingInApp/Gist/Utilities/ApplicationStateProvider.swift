import CioInternalCommon
import Foundation
import UIKit

/// Protocol for abstracting UIApplication state access.
/// Enables testing with controlled app states instead of relying on
/// the implicit simulator/device state during test execution.
protocol ApplicationStateProvider: AutoMockable {
    /// Returns the current application state.
    /// Must be called from the main thread.
    @MainActor
    var applicationState: UIApplication.State { get }
}

// sourcery: InjectRegisterShared = "ApplicationStateProvider"
/// Production implementation that wraps UIApplication.shared.
/// Returns the actual application state from the system.
struct RealApplicationStateProvider: ApplicationStateProvider {
    @MainActor
    var applicationState: UIApplication.State {
        UIApplication.shared.applicationState
    }
}
