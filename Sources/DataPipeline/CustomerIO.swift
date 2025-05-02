import CioInternalCommon
import CioTrackingMigration

public extension CustomerIO {
    /**
     Initialize the shared `instance` of `CustomerIO`.
     Call this function when your app launches, before using `CustomerIO.instance`.
     */
    @available(iOSApplicationExtension, unavailable)
    static func initialize(withConfig config: SDKConfigBuilderResult) {
        // SdkConfig isn't currently stored anywhere since it wasn't required. If needed later, we
        // can introduce an option to store and retrieve it.
        let (sdkConfig, cdpConfig) = config

        // set the logLevel for ConsoleLogger before initializing any module
        DIGraphShared.shared.logger.setLogLevel(sdkConfig.logLevel)
        // initialize DataPipeline module with the provided configuration
        let implementation = DataPipeline.initialize(moduleConfig: cdpConfig)
        initialize(implementation: implementation)

        // Handle logged-in user from Journeys to CDP and check
        // if any unprocessed tasks are pending in the background queue.
        if let siteId = cdpConfig.migrationSiteId {
            let migrationAssistant = DataPipelineMigrationAssistant(handler: implementation)
            migrationAssistant.performMigration(siteId: siteId)
        }
    }

    /**
     Common initialization method for setting up the shared `CustomerIO` instance.
     This method is intended to be used by both actual implementations and in tests, ensuring that tests closely mimic the real-world implementation.
     */
    private static func initialize(implementation: DataPipelineInstance) {
        initializeSharedInstance(with: implementation)
    }

    #if DEBUG
    // Methods to set up the test environment.
    // Integration tests use the actual implementation.

    @discardableResult
    static func setUpSharedInstanceForIntegrationTest(diGraphShared: DIGraphShared, moduleConfig: DataPipelineConfigOptions) -> DataPipelineInstance {
        let implementation = DataPipeline.setUpSharedInstanceForIntegrationTest(diGraphShared: diGraphShared, config: moduleConfig)
        initialize(implementation: implementation)
        return implementation
    }

    static func resetTestEnvironment() {
        CustomerIO.resetSharedTestEnvironment()
        DataPipeline.resetTestEnvironment()
    }
    #endif
}
