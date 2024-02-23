import CioInternalCommon

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

        let implementation = DataPipeline.initialize(moduleConfig: cdpConfig)
        // set the logLevel for ConsoleLogger
        DIGraphShared.shared.logger.setLogLevel(sdkConfig.logLevel)
        // enable Analytics logs accordingly to logLevel
        CustomerIO.shared.setDebugLogsEnabled(sdkConfig.logLevel == CioLogLevel.debug)

        initialize(implementation: implementation)
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
