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

        // FIXME: [CDP] Update shared instance method to support DataPipeline
        CustomerIO.shared.implementation = implementation
        // let sdkConfig = SdkConfig.Factory.create(siteId: "", apiKey: "", region: .US)
        // let newDiGraph = DIGraph(sdkConfig: sdkConfig)
        // initializeSharedInstance(with: implementation, diGraph: newDiGraph, module: TrackingModuleHookProvider(), cleanupRepositoryImp: newDiGraph.cleanupRepository)
    }
}
