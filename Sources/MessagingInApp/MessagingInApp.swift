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

    // MARK: static initialized functions for customers.

    // static functions are identical to initialize functions in InAppInstance protocol to try and make a more convenient
    // API for customers. Customers can use `MessagingInApp.initialize(...)` instead of `MessagingInApp.shared.initialize(...)`.
    // Trying to follow the same API as `CustomerIO` class with `initialize()`.

    public static func initialize(organizationId: String) {
        Self.shared.initialize(organizationId: organizationId)
    }

    public static func initialize(organizationId: String, eventListener: InAppEventListener) {
        Self.shared.initialize(organizationId: organizationId, eventListener: eventListener)
    }

    // MARK: initialize functions to initialize module.

    // Multiple initialize functions to inherit the InAppInstance protocol which contains multiple initialize functions.

    public func initialize(organizationId: String) {
        commonInitialize(organizationId: organizationId, eventListener: nil)
    }

    public func initialize(organizationId: String, eventListener: InAppEventListener) {
        commonInitialize(organizationId: organizationId, eventListener: eventListener)
    }

    private func commonInitialize(organizationId: String, eventListener: InAppEventListener?) {
        guard let implementation = implementation else {
            sdkNotInitializedAlert("CustomerIO class has not yet been initialized. Request to initialize the in-app module has been ignored.")
            return
        }

        initialize()

        if let eventListener = eventListener {
            implementation.initialize(organizationId: organizationId, eventListener: eventListener)
        } else {
            implementation.initialize(organizationId: organizationId)
        }
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
