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
        initializeSharedInstance(with: implementation, diGraph: newDiGraph)
    }

    #if DEBUG
    /// Initializer for Integration Tests to update the DataPipeline instances.
    /// To be used for testing purposes only.
    static func initializeIntegrationTestsInstance(diGraph: DIGraph, moduleConfig: DataPipelineConfigOptions) {
        let implementation = DataPipeline.createAndSetSharedTestInstance(diGraphShared: DIGraphShared.shared, config: moduleConfig)
        initializeSharedInstance(with: implementation, diGraph: diGraph)
    }

    /// Make testing the singleton `instance` possible.
    /// Note: It's recommended to delete app data before doing this to prevent loading persisted credentials
    static func resetSharedTestInstance() {
        DataPipeline.resetSharedTestInstance()
    }
    #endif
}
