import CioInternalCommon

public extension CustomerIO {
    /**
     Initialize the shared `instance` of `CustomerIO`.
     Call this function when your app launches, before using `CustomerIO.instance`.
     */
    @available(iOSApplicationExtension, unavailable)
    static func initialize(
        writeKey: String,
        logLevel: CioLogLevel = .error,
        configure configureHandler: ((inout DataPipelineConfigOptions) -> Void)?
    ) {
        var cdpConfig = DataPipelineConfigOptions.Factory.create(writeKey: writeKey)

        if let configureHandler = configureHandler {
            configureHandler(&cdpConfig)
        }

        let implementation = DataPipeline.initialize(moduleConfig: cdpConfig)

        let sdkConfig = SdkConfig.Factory.create(siteId: "", apiKey: "", region: .US)
        let newDiGraph = DIGraph(sdkConfig: sdkConfig)
        initialize(implementation: implementation, diGraph: newDiGraph)
    }

    /**
     Common initialization method for setting up the shared `CustomerIO` instance.
     This method is intended to be used by both actual implementations and in tests, ensuring that tests closely mimic the real-world implementation.
     */
    private static func initialize(implementation: DataPipelineInstance, diGraph: DIGraph) {
        initializeSharedInstance(with: implementation, diGraph: diGraph)
    }

    #if DEBUG
    /**
     Initializes and configures `CustomerIO` shared and implementation instance, for testing purpose only.
     */
    static func setUpSharedTestInstance(diGraphShared: DIGraphShared, diGraph: DIGraph, moduleConfig: DataPipelineConfigOptions) {
        let implementation = DataPipeline.setUpSharedTestInstance(diGraphShared: diGraphShared, config: moduleConfig)
        initialize(implementation: implementation, diGraph: diGraph)
    }

    /**
     Resets the shared  `CustomerIO` and `DataPipeline` instance to their initial state, only for testing purpose.
     */
    static func resetSharedTestInstances() {
        CustomerIO.resetSharedTestInstance()
        DataPipeline.resetSharedTestInstance()
    }
    #endif
}
