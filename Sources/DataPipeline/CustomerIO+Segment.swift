import CioInternalCommon
import Foundation
import Segment

// MARK: - System Modifiers

public extension CustomerIO {
    /// Enable/Disable analytics capture
    var enabled: Bool {
        DataPipeline.shared.analytics.enabled
    }

    /// Returns the anonymousId currently in use.
    var anonymousId: String {
        DataPipeline.shared.analytics.anonymousId
    }

    /// Returns the userId that was specified in the last identify call.
    var userId: String? {
        DataPipeline.shared.analytics.userId
    }

    /// Returns the current operating mode this instance was given.
    var operatingMode: OperatingMode {
        DataPipeline.shared.analytics.operatingMode
    }

    /// Adjusts the flush interval post configuration.
    var flushInterval: TimeInterval {
        DataPipeline.shared.analytics.flushInterval
    }

    /// Adjusts the flush-at count post configuration.
    var flushAt: Int {
        DataPipeline.shared.analytics.flushAt
    }

    /// Returns a list of currently active flush policies.
    var flushPolicies: [FlushPolicy] {
        DataPipeline.shared.analytics.flushPolicies
    }

    /// Returns the traits that were specified in the last identify call.
    func traits<T: Codable>() -> T? {
        DataPipeline.shared.analytics.traits()
    }

    /// Returns the traits that were specified in the last identify call, as a dictionary.
    func traits() -> [String: Any]? {
        DataPipeline.shared.analytics.traits()
    }

    /// Tells this instance of Analytics to flush any queued events up to Segment.com.  This command will also
    /// be sent to each plugin present in the system.  A completion handler can be optionally given and will be
    /// called when flush has completed.
    func flush(completion: (() -> Void)? = nil) {
        DataPipeline.shared.analytics.flush(completion: completion)
    }

    /// Resets this instance of Analytics to a clean slate.  Traits, UserID's, anonymousId, etc are all cleared or reset.  This
    /// command will also be sent to each plugin present in the system.
    func reset() {
        DataPipeline.shared.analytics.reset()
    }

    /// Retrieve the version of this library in use.
    /// - Returns: A string representing the version in "BREAKING.FEATURE.FIX" format.
    func version() -> String {
        DataPipeline.shared.analytics.version()
    }
}

public extension CustomerIO {
    /// Manually retrieve the settings that were supplied from Segment.com.
    /// - Returns: A Settings object containing integration settings, tracking plan, etc.
    func settings() -> Settings? {
        DataPipeline.shared.analytics.settings()
    }

    /// Manually enable a destination plugin.  This is useful when a given DestinationPlugin doesn't have any Segment tie-ins at all.
    /// This will allow the destination to be processed in the same way within this library.
    /// - Parameters:
    ///   - plugin: The destination plugin to enable.
    func manuallyEnableDestination(plugin: DestinationPlugin) {
        DataPipeline.shared.analytics.manuallyEnableDestination(plugin: plugin)
    }
}

public extension CustomerIO {
    /// Determine if there are any events that have yet to be sent to Segment
    var hasUnsentEvents: Bool {
        DataPipeline.shared.analytics.hasUnsentEvents
    }

    /// Provides a list of finished, but unsent events.
    var pendingUploads: [URL]? {
        DataPipeline.shared.analytics.pendingUploads
    }

    /// Purge all pending event upload files.
    func purgeStorage() {
        DataPipeline.shared.analytics.purgeStorage()
    }

    /// Purge a single event upload file.
    func purgeStorage(fileURL: URL) {
        DataPipeline.shared.analytics.purgeStorage(fileURL: fileURL)
    }

    /// Wait until the Analytics object has completed startup.
    /// This method is primarily useful for command line utilities where
    /// it's desirable to wait until the system is up and running
    /// before executing commands.  GUI apps could potentially use this via
    /// a background thread if needed.
    func waitUntilStarted() {
        DataPipeline.shared.analytics.waitUntilStarted()
    }
}

public extension CustomerIO {
    /**
     Call openURL as needed or when instructed to by either UIApplicationDelegate or UISceneDelegate.
     This is necessary to track URL referrers across events.  This method will also iterate
     any plugins that are watching for openURL events.

     Example:
     ```
     func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
         let myStruct = MyStruct(options)
         analytics?.openURL(url, options: options)
         return true
     }
     ```
     */
    func openURL<T: Codable>(_ url: URL, options: T? = nil) {
        DataPipeline.shared.analytics.openURL(url, options: options)
    }

    /**
     Call openURL as needed or when instructed to by either UIApplicationDelegate or UISceneDelegate.
     This is necessary to track URL referrers across events.  This method will also iterate
     any plugins that are watching for openURL events.

     Example:
     ```
     func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
         analytics?.openURL(url, options: options)
         return true
     }
     ```
     */
    func openURL(_ url: URL, options: [String: Any] = [:]) {
        DataPipeline.shared.analytics.openURL(url, options: options)
    }
}

extension DataPipelineConfigOptions {
    func toSegmentConfiguration() -> Configuration {
        let result = Configuration(writeKey: cdpApiKey)
        result.trackApplicationLifecycleEvents(trackApplicationLifecycleEvents)
        result.flushAt(flushAt)
        result.flushInterval(flushInterval)
        // Force set to false as we will never add Segment destination
        // User can disable CIO destination to achieve same results
        result.autoAddSegmentDestination(false)
        result.apiHost(apiHost)
        result.cdnHost(cdnHost)
        result.flushPolicies(flushPolicies)
        return result
    }
}
