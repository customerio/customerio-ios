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

    /// Logged when `CustomerIO.initialize(withConfig:)` runs again with the module registered. The
    /// first configuration stays in effect: its registrations and observers are already live, and
    /// swapping them mid-flight would orphan activities started under the previous config.
    func reconfigurationNotSupported() {
        error(
            "Live Activities module is already initialized — keeping the first configuration and ignoring this one. Reconfiguration is not supported. Initializing the Customer.io SDK twice (for example a wrapper's automatic initialization followed by an explicit initialize call) is the usual cause.",
            liveActivitiesTag,
            nil
        )
    }

    /// Logged when a Customer.io Live Activity URL reaches the SDK on a system older than iOS 16.2,
    /// where the module deliberately never initializes. ``moduleNotInitialized()`` must not be used
    /// here: it tells the developer to register the module, which cannot help on an OS that has no
    /// Live Activities at all.
    func liveActivitiesUnsupportedOS() {
        info(
            "Live Activities require iOS 16.2 or later, so no `opened` metric is reported for this Customer.io Live Activity URL. Its redirect is still returned, so deep-link routing is unaffected.",
            liveActivitiesTag
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
