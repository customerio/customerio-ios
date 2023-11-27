import CioInternalCommon
import Foundation
import Segment

public class CIODataPipeline {
    // Private static instance of Analytics, created only once.
    private static var analytics: Analytics = .init(configuration: Configuration.defaultConfiguration)

    // Private initializer to enforce singleton usage, prevents external instantiation.
    private init() {}

    // Static method to access the singleton Analytics instance.
    public static func shared() -> Analytics {
        analytics
    }

    // Method to reinitialize Analytics with a new configuration.
    public static func initialize(configuration: Configuration) {
        analytics = Analytics(configuration: configuration)
    }
}

// MARK: - System Modifiers

public extension CustomerIO {
    /// Enable/Disable analytics capture
    var enabled: Bool {
        CIODataPipeline.shared().enabled
    }

    /// Returns the anonymousId currently in use.
    var anonymousId: String {
        CIODataPipeline.shared().anonymousId
    }

    /// Returns the userId that was specified in the last identify call.
    var userId: String? {
        CIODataPipeline.shared().userId
    }

    /// Returns the current operating mode this instance was given.
    var operatingMode: OperatingMode {
        CIODataPipeline.shared().operatingMode
    }

    /// Adjusts the flush interval post configuration.
    var flushInterval: TimeInterval {
        CIODataPipeline.shared().flushInterval
    }

    /// Adjusts the flush-at count post configuration.
    var flushAt: Int {
        CIODataPipeline.shared().flushAt
    }

    /// Returns a list of currently active flush policies.
    var flushPolicies: [FlushPolicy] {
        CIODataPipeline.shared().flushPolicies
    }

    /// Returns the traits that were specified in the last identify call.
    func traits<T: Codable>() -> T? {
        CIODataPipeline.shared().traits()
    }

    /// Returns the traits that were specified in the last identify call, as a dictionary.
    func traits() -> [String: Any]? {
        CIODataPipeline.shared().traits()
    }

    /// Tells this instance of Analytics to flush any queued events up to Segment.com.  This command will also
    /// be sent to each plugin present in the system.  A completion handler can be optionally given and will be
    /// called when flush has completed.
    func flush(completion: (() -> Void)? = nil) {
        CIODataPipeline.shared().flush(completion: completion)
    }

    /// Resets this instance of Analytics to a clean slate.  Traits, UserID's, anonymousId, etc are all cleared or reset.  This
    /// command will also be sent to each plugin present in the system.
    func reset() {
        CIODataPipeline.shared().reset()
    }

    /// Retrieve the version of this library in use.
    /// - Returns: A string representing the version in "BREAKING.FEATURE.FIX" format.
    func version() -> String {
        CIODataPipeline.shared().version()
    }
}

public extension CustomerIO {
    /// Manually retrieve the settings that were supplied from Segment.com.
    /// - Returns: A Settings object containing integration settings, tracking plan, etc.
    func settings() -> Settings? {
        CIODataPipeline.shared().settings()
    }

    /// Manually enable a destination plugin.  This is useful when a given DestinationPlugin doesn't have any Segment tie-ins at all.
    /// This will allow the destination to be processed in the same way within this library.
    /// - Parameters:
    ///   - plugin: The destination plugin to enable.
    func manuallyEnableDestination(plugin: DestinationPlugin) {
        CIODataPipeline.shared().manuallyEnableDestination(plugin: plugin)
    }
}

public extension CustomerIO {
    /// Determine if there are any events that have yet to be sent to Segment
    var hasUnsentEvents: Bool {
        CIODataPipeline.shared().hasUnsentEvents
    }

    /// Provides a list of finished, but unsent events.
    var pendingUploads: [URL]? {
        CIODataPipeline.shared().pendingUploads
    }

    /// Purge all pending event upload files.
    func purgeStorage() {
        CIODataPipeline.shared().purgeStorage()
    }

    /// Purge a single event upload file.
    func purgeStorage(fileURL: URL) {
        CIODataPipeline.shared().purgeStorage(fileURL: fileURL)
    }

    /// Wait until the Analytics object has completed startup.
    /// This method is primarily useful for command line utilities where
    /// it's desirable to wait until the system is up and running
    /// before executing commands.  GUI apps could potentially use this via
    /// a background thread if needed.
    func waitUntilStarted() {
        CIODataPipeline.shared().waitUntilStarted()
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
        CIODataPipeline.shared().openURL(url, options: options)
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
        CIODataPipeline.shared().openURL(url, options: options)
    }
}
