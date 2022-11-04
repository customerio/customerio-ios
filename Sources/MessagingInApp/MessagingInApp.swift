import CioTracking
import Common
import Foundation
import Gist

public protocol MessagingInAppInstance: AutoMockable {
    func initialize(organizationId: String)
}

public class MessagingInApp: ModuleTopLevelObject<MessagingInAppInstance>, MessagingInAppInstance {
    @Atomic public private(set) static var shared = MessagingInApp()

    override internal init(implementation: MessagingInAppInstance, sdkInitializedUtil: SdkInitializedUtil) {
        super.init(implementation: implementation, sdkInitializedUtil: sdkInitializedUtil)
    }

    // singleton constructor
    override private init() {
        super.init()
    }

    override public func getImplementationInstance(siteId: SiteId, diGraph: DIGraph) -> MessagingInAppInstance {
        let logger = diGraph.logger
        logger.debug("Setting up MessagingInApp module...")

        // Register MessagingPush module hooks now that the module is being initialized.
        let hooks = diGraph.hooksManager
        let moduleHookProvider = MessagingInAppModuleHookProvider(siteId: siteId)
        hooks.add(key: .messagingInApp, provider: moduleHookProvider)

        let newInstance = MessagingInAppImplementation(siteId: siteId, diGraph: diGraph)

        logger.info("MessagingInApp module setup with SDK")

        return newInstance
    }

    public func initialize(organizationId: String) {
        implementation?.initialize(organizationId: organizationId)
    }
}
