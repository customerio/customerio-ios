import CioInternalCommon
import CioMigration

class DataPipelineMigrationHandler: DataPipelineTrackingMigrationAction {
    func processAlreadyIdentifiedUser(identifier: String) {
        print("identifier is \(identifier)")
    }

    func processIdentifyFromBGQ(identifier: String, timestamp: String, body: [String: Any]?) {
        // something
    }

    func processScreenEventFromBGQ(identifier: String, name: String, timestamp: String?, properties: [String: Any]) {
        // something
    }

    func processEventFromBGQ(identifier: String, name: String, timestamp: String?, properties: [String: Any]) {
        // something
    }

    func processDeleteTokenFromBGQ(identifier: String, token: String, timestamp: String) {
        // something
    }

    func processRegisterDeviceFromBGQ(identifier: String, token: String, timestamp: String, attributes: [String: Any]?) {
        // something
    }

    func processPushMetricsFromBGQ(token: String, event: CioInternalCommon.Metric, deliveryId: String, timestamp: String, metaData: [String: Any]) {
        // something
    }
}

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

        // Handle logged-in user from Journeys to CDP and check
        // if any unprocessed tasks are pending in the background queue.
        let migrationHandler = DataPipelineMigrationHandler()
        let migrationAssistant = DataPipelineTrackingMigrationAssistant(handler: migrationHandler, diGraph: newDiGraph)
        migrationAssistant.performMigration(for: DataPipeline.shared.analytics.userId)
    }

    /**
     Common initialization method for setting up the shared `CustomerIO` instance.
     This method is intended to be used by both actual implementations and in tests, ensuring that tests closely mimic the real-world implementation.
     */
    private static func initialize(implementation: DataPipelineInstance, diGraph: DIGraph) {
        initializeSharedInstance(with: implementation, diGraph: diGraph)
    }

    #if DEBUG
    // Methods to set up the test environment.
    // Integration tests use the actual implementation.

    @discardableResult
    static func setUpSharedInstanceForIntegrationTest(diGraphShared: DIGraphShared, diGraph: DIGraph, moduleConfig: DataPipelineConfigOptions) -> DataPipelineInstance {
        let implementation = DataPipeline.setUpSharedInstanceForIntegrationTest(diGraphShared: diGraphShared, config: moduleConfig)
        initialize(implementation: implementation, diGraph: diGraph)
        return implementation
    }

    static func resetTestEnvironment() {
        CustomerIO.resetSharedTestEnvironment()
        DataPipeline.resetTestEnvironment()
    }
    #endif
}
