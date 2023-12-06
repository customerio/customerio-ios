import CioInternalCommon

public extension CustomerIO {
    /**
     Initialize the shared `instance` of `CustomerIO`.
     Call this function when your app launches, before using `CustomerIO.instance`.
     */
    @available(iOSApplicationExtension, unavailable)
    static func initialize(
        writeKey: String,
        configure configureHandler: ((inout SdkConfig, inout DataPipelineConfigOptions) -> Void)?
    ) {
        var sdkConfig = SdkConfig.Factory.create(siteId: "", apiKey: "", region: .US)
        var cdpConfig = DataPipelineConfigOptions.Factory.create(writeKey: writeKey)

        if let configureHandler = configureHandler {
            configureHandler(&sdkConfig, &cdpConfig)
        }

        let newDiGraph = DIGraph(sdkConfig: sdkConfig)
        let implementation = DataPipeline.initialize(moduleConfig: cdpConfig)

        // FIXME: [CDP] Update shared instance method to support DataPipeline
        // initializeSharedInstance(with: implementation, diGraph: newDiGraph, module: TrackingModuleHookProvider(), cleanupRepositoryImp: newDiGraph.cleanupRepository)
    }
}
