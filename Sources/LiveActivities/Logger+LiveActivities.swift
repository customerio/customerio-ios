import CioInternalCommon
import Foundation

private let liveActivitiesTag = "LiveActivities"

extension Logger {
    func moduleNotInitialized() {
        error(
            "Live Activities module is not initialized. Add LiveActivitiesModule via SDKConfigBuilder.addModule(LiveActivitiesModule(config: ...)) before CustomerIO.initialize(withConfig:).",
            liveActivitiesTag,
            nil
        )
    }

    func reconfigurationNotSupported() {
        error(
            "Live Activities module is already initialized. Reconfiguration is not supported.",
            liveActivitiesTag,
            nil
        )
    }

    func liveActivityTypeNotRegistered(_ typeName: String) {
        error(
            "Live Activities: start ignored — attributes type '\(typeName)' was not registered via LiveActivityConfigBuilder.register(...).",
            liveActivitiesTag,
            nil
        )
    }
}
