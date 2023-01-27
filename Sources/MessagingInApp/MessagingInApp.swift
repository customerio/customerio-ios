import CioTracking
import Common
import Foundation
import Gist

public protocol MessagingInAppInstance: AutoMockable {
    // sourcery:Name=initialize
    func initialize()
    // sourcery:Name=initializeEventListener
    func initialize(eventListener: InAppEventListener)

    @available(*, deprecated, message: "Parameter organizationId no longer being used. Remove the parameter from your function call to migrate to new function.")
    // sourcery:Name=initializeOrganizationId
    func initialize(organizationId: String)

    @available(*, deprecated, message: "Parameter organizationId no longer being used. Remove the parameter from your function call to migrate to new function.")
    // sourcery:Name=initializeOrganizationIdEventListener
    func initialize(organizationId: String, eventListener: InAppEventListener)
}

public class MessagingInApp: ModuleTopLevelObject<MessagingInAppInstance>, MessagingInAppInstance {
    @Atomic public internal(set) static var shared = MessagingInApp()

    // constructor that is called by test classes
    // This function's job is to populate the `shared` property with
    // overrides such as DI graph.
    override internal init(implementation: MessagingInAppInstance?, sdkInitializedUtil: SdkInitializedUtil) {
        super.init(implementation: implementation, sdkInitializedUtil: sdkInitializedUtil)
    }

    // constructor used in production with default DI graph
    // singleton constructor
    override private init() {
        super.init()
    }

    // for testing
    internal static func resetSharedInstance() {
        Self.shared = MessagingInApp()
    }

    // Initialize SDK module
    public static func initialize() {
        Self.shared.initialize()
    }

    public static func initialize(eventListener: InAppEventListener) {
        Self.shared.initialize(eventListener: eventListener)
    }

    @available(*, deprecated, message: "Parameter organizationId no longer being used. Remove the parameter from your function call to migrate to new function.")
    public static func initialize(organizationId: String) {
        Self.shared.initialize(organizationId: organizationId)
    }

    @available(*, deprecated, message: "Parameter organizationId no longer being used. Remove the parameter from your function call to migrate to new function.")
    public static func initialize(organizationId: String, eventListener: InAppEventListener) {
        Self.shared.initialize(organizationId: organizationId, eventListener: eventListener)
    }

    @available(*, deprecated, message: "Parameter organizationId no longer being used. Remove the parameter from your function call to migrate to new function.")
    public func initialize(organizationId: String) {
        initialize()
    }

    @available(*, deprecated, message: "Parameter organizationId no longer being used. Remove the parameter from your function call to migrate to new function.")
    public func initialize(organizationId: String, eventListener: InAppEventListener) {
        initialize(eventListener: eventListener)
    }

    public func initialize() {
        guard let implementation = implementation else {
            sdkNotInitializedAlert("CustomerIO class has not yet been initialized. Request to initialize the in-app module has been ignored.")
            return
        }

        initializeModuleIfSdkInitialized()

        implementation.initialize()
    }

    public func initialize(eventListener: InAppEventListener) {
        guard let implementation = implementation else {
            sdkNotInitializedAlert("CustomerIO class has not yet been initialized. Request to initialize the in-app module has been ignored.")
            return
        }

        initializeModuleIfSdkInitialized()

        implementation.initialize(eventListener: eventListener)
    }

    override public func inititlizeModule(diGraph: DIGraph) {
        let logger = diGraph.logger
        logger.debug("Setting up in-app module...")

        // Register MessagingPush module hooks now that the module is being initialized.
        let hooks = diGraph.hooksManager
        let moduleHookProvider = MessagingInAppModuleHookProvider()
        hooks.add(key: .messagingInApp, provider: moduleHookProvider)

        logger.info("In-app module setup with SDK")
    }

    override public func getImplementationInstance(diGraph: DIGraph) -> MessagingInAppInstance {
        MessagingInAppImplementation(diGraph: diGraph)
    }
}
