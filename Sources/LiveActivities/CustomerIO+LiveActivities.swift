import CioInternalCommon
import Foundation

/// Extension to expose the Live Activities module through CustomerIO.
public extension CustomerIO {
    /// Access the Live Activities module. Register it via
    /// `SDKConfigBuilder.addModule(LiveActivitiesModule(config: ...))` before
    /// `CustomerIO.initialize(withConfig:)` to enable Live Activities.
    ///
    /// Before initialization (or on iOS < 16.2) this returns a stub that logs an error and no-ops
    /// when used — it never throws or crashes because the module wasn't ready yet.
    static var liveActivities: LiveActivitiesInstance {
        LiveActivitiesModuleState.shared.current
    }
}
