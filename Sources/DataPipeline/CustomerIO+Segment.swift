import CioAnalytics
import CioInternalCommon
import Foundation

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

    /// Tells this instance of CustomerIO to flush any queued events. This command will also
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
}

public extension CustomerIO {
    /// Determine if there are any events that have yet to be sent
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

extension DataPipelineConfigOptions {
    func toSegmentConfiguration() -> Configuration {
        let result = Configuration(writeKey: cdpApiKey)
        result.trackApplicationLifecycleEvents(trackApplicationLifecycleEvents)
        result.flushAt(flushAt)
        result.flushInterval(flushInterval)
        // Set settings to nil as we don't want to add default Segment integration
        result.defaultSettings(nil)
        // Force set to false as we will never add Segment destination
        // User can disable CIO destination to achieve same results
        result.autoAddSegmentDestination(false)
        result.apiHost(apiHost)
        result.cdnHost(cdnHost)
        result.flushPolicies(flushPolicies)
        return result
    }
}
