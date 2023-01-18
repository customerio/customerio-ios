import CioTracking
import Common
import Foundation
import Gist

public protocol MessagingInAppInstance: AutoMockable {
    func initialize(organizationId: String)
    // sourcery:Name=initializeEventListener
    func initialize(organizationId: String, eventListener: InAppEventListener)
}

public class MessagingInApp: ModuleTopLevelObject<MessagingInAppInstance>, MessagingInAppInstance {
    @Atomic public private(set) static var shared = MessagingInApp()

    override internal init(implementation: MessagingInAppInstance?, sdkInitializedUtil: SdkInitializedUtil) {
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

    // testing constructor
    internal static func initialize(organizationId: String, eventListener: InAppEventListener?, implementation: MessagingInAppInstance?, sdkInitializedUtil: SdkInitializedUtil) {
        Self.shared = MessagingInApp(implementation: implementation, sdkInitializedUtil: sdkInitializedUtil)

        if let eventListener = eventListener {
            Self.initialize(organizationId: organizationId, eventListener: eventListener)
        } else {
            Self.initialize(organizationId: organizationId)
        }
    }

    // Initialize SDK module
    public static func initialize(organizationId: String) {
        Self.shared.initialize(organizationId: organizationId)
    }

    public static func initialize(organizationId: String, eventListener: InAppEventListener) {
        Self.shared.initialize(organizationId: organizationId, eventListener: eventListener)
    }

    public func initialize(organizationId: String) {
        guard let implementation = implementation else {
            sdkNotInitializedAlert("CustomerIO class has not yet been initialized. Request to initialize the in-app module has been ignored.")
            return
        }

        initialize()

        implementation.initialize(organizationId: organizationId)
    }

    public func initialize(organizationId: String, eventListener: InAppEventListener) {
        guard let implementation = implementation else {
            sdkNotInitializedAlert("CustomerIO class has not yet been initialized. Request to initialize the in-app module has been ignored.")
            return
        }

        initialize()

        implementation.initialize(organizationId: organizationId, eventListener: eventListener)
    }

    override public func inititlize(diGraph: DIGraph) {
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
