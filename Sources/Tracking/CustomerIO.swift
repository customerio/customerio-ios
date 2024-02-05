import CioDataPipelines
import CioInternalCommon
import Foundation

public extension CustomerIOInstance {
    func identify(
        identifier: String
    ) {
        identify(identifier: identifier, body: EmptyRequestBody())
    }

    func track(
        name: String
    ) {
        track(name: name, data: EmptyRequestBody())
    }

    func screen(
        name: String
    ) {
        screen(name: name, data: EmptyRequestBody())
    }
}

public extension CustomerIO {
    /**
     Initialize the shared `instance` of `CustomerIO`.
     Call this function when the app launches, before using `CustomerIO.instance`.
     */
    @available(iOSApplicationExtension, unavailable)
    static func initialize(
        siteId: String,
        apiKey: String,
        region: Region,
        configure configureHandler: ((inout SdkConfig) -> Void)?
    ) {
        var sdkConfig = SdkConfig.Factory.create(siteId: siteId, apiKey: apiKey, region: region)

        if let configureHandler = configureHandler {
            configureHandler(&sdkConfig)
        }

        let implementation = DataPipeline.initialize(moduleConfig: DataPipelineConfigOptions.Factory.create(sdkConfig: sdkConfig))
        let newDiGraph = DIGraph(sdkConfig: sdkConfig)
        initialize(implementation: implementation, diGraph: newDiGraph)
    }

    /**
     Initialize the shared `instance` of `CustomerIO` for Notification Service Extension.
     */
    @available(iOS, unavailable)
    @available(iOSApplicationExtension, introduced: 13.0)
    static func initialize(
        siteId: String,
        apiKey: String,
        region: Region,
        configure configureHandler: ((inout NotificationServiceExtensionSdkConfig) -> Void)?
    ) {
        var newSdkConfig = NotificationServiceExtensionSdkConfig.Factory.create(siteId: siteId, apiKey: apiKey, region: region)
        if let configureHandler = configureHandler {
            configureHandler(&newSdkConfig)
        }

        let sdkConfig = newSdkConfig.toSdkConfig()
        let newDiGraph = DIGraph(sdkConfig: sdkConfig)
        let implementation = DataPipeline.initialize(moduleConfig: DataPipelineConfigOptions.Factory.create(sdkConfig: sdkConfig))

        initializeSharedInstance(with: implementation, diGraph: newDiGraph)
    }

    /**
     Common initialization method for setting up the shared `CustomerIO` instance.
     This method is intended to be used by both actual implementations and in tests, ensuring that tests closely mimic the real-world implementation.
     */
    private static func initialize(implementation: CustomerIOInstance, diGraph: DIGraph) {
        initializeSharedInstance(with: implementation, diGraph: diGraph)

        // Handle any unprocessed tasks pending in the background queue.
        let migrationAssistant = diGraph.dataPipelineMigrationAssistant
        migrationAssistant.handleQueueBacklog()

        let sdkConfig = diGraph.sdkConfig
        // automatically add the Logger plugin if logLevel is debug
        if sdkConfig.logLevel == .debug {
            CustomerIO.shared.setDebugLogsEnabled(true)
        }
        // automatically add the AutoTrackingScreenViews plugin if autoTrackScreenViews is enabled
        if sdkConfig.autoTrackScreenViews {
            DataPipeline.shared.analytics.add(plugin: AutoTrackingScreenViews(filterAutoScreenViewEvents: sdkConfig.filterAutoScreenViewEvents, autoScreenViewBody: sdkConfig.autoScreenViewBody))
        }
    }

    #if DEBUG
    // Methods to set up the test environment.
    // Integration tests use the actual implementation.

    @discardableResult
    static func setUpSharedInstanceForIntegrationTest(diGraphShared: DIGraphShared, diGraph: DIGraph, autoAddCustomerIODestination: Bool = false) -> CustomerIOInstance {
        let sdkConfig = diGraph.sdkConfig
        var moduleConfig = DataPipelineConfigOptions.Factory.create(sdkConfig: sdkConfig)
        // allow overriding autoAddCustomerIODestination so http requests can be ignored during tests
        // autoAddCustomerIODestination cannot be provided directly in any graph as it DataPipelineConfigOptions property,
        // and DataPipelineConfigOptions is not a part of any graph yet, so added it as a parameter to this method for convenience
        moduleConfig.autoAddCustomerIODestination = autoAddCustomerIODestination

        let implementation = DataPipeline.setUpSharedInstanceForIntegrationTest(diGraphShared: diGraphShared, config: moduleConfig)
        initialize(implementation: implementation, diGraph: diGraph)
        return implementation
    }
    #endif
}
