import CioInternalCommon
import Foundation

/// Extension to expose the Location module through CustomerIO.
public extension CustomerIO {
    /// Access the Location module. Register the module via `SDKConfigBuilder.addModule(LocationModule(config: ...))` before `CustomerIO.initialize(withConfig:)` to enable Location.
    /// Before initialization, returns an implementation that logs an error when used.
    static var location: LocationServices {
        LocationModuleState.shared.current
    }
}
