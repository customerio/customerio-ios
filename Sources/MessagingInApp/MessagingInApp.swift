import CioTracking
import Common
import Foundation
import Gist

public protocol MessagingInAppInstance: AutoMockable {
    func initialize(organizationId: String)
}

public class MessagingInApp: ModuleTopLevelObject<MessagingInAppInstance>, MessagingInAppInstance {
    @Atomic public private(set) static var shared = MessagingInApp()

    // testing constructor
    override internal init(implementation: MessagingInAppInstance, sdkInitializedUtil: SdkInitializedUtil) {
        super.init(implementation: implementation, sdkInitializedUtil: sdkInitializedUtil)
    }

    // singleton constructor
    override private init() {
        super.init()
    }

    // for testing
    internal static func resetSharedInstance() {
        Self.shared = MessagingInApp()
    }

    // Initialize SDK module
    public static func initialize(organizationId: String) {
        Self.shared.initialize(organizationId: organizationId)
    }

    public func initialize(organizationId: String) {
        initialize() // enables features such as setting up hooks

        implementation?.initialize(organizationId: organizationId)
    }

    override public func inititlize(diGraph: DIGraph) {
        let logger = diGraph.logger
        logger.debug("Setting up MessagingInApp module...")

        // Register MessagingPush module hooks now that the module is being initialized.
        let hooks = diGraph.hooksManager
        let moduleHookProvider = MessagingInAppModuleHookProvider()
        hooks.add(key: .messagingInApp, provider: moduleHookProvider)

        logger.info("MessagingInApp module setup with SDK")
    }

    override public func getImplementationInstance(diGraph: DIGraph) -> MessagingInAppInstance {
        MessagingInAppImplementation(diGraph: diGraph)
    }
}
