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
     Call this function when your app launches, before using `CustomerIO.instance`.
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

        // Check if any unprocessed tasks are pending in the background queue.
        let newDiGraph = DIGraph(sdkConfig: sdkConfig)
        let migrationAssistant = newDiGraph.dataPipelineMigrationAssistant
        migrationAssistant.handleQueueBacklog()

        initializeSharedInstance(with: implementation, diGraph: newDiGraph)

        if sdkConfig.logLevel == .debug {
            CustomerIO.shared.setDebugLogsEnabled(true)
        }
        if sdkConfig.autoTrackScreenViews {
            // automatically add the AutoTrackingScreenViews plugin
            DataPipeline.shared.analytics.add(plugin: AutoTrackingScreenViews(filterAutoScreenViewEvents: sdkConfig.filterAutoScreenViewEvents, autoScreenViewBody: sdkConfig.autoScreenViewBody))
        }
    }

    // Initialize for Notification Service Extension
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

    // Initialize for Integration Tests
    static func initializeIntegrationTests(diGraph: DIGraph) {
        // FIXME: [CDP] Fix tests using DataPipeline
        // let implementation = CustomerIOImplementation(diGraph: diGraph)
        // initializeSharedInstance(with: implementation, diGraph: diGraph)
    }
}
