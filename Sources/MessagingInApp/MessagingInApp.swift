import CioInternalCommon
import Foundation

public protocol MessagingInAppInstance: AutoMockable {
    // sourcery:Name=setEventListener
    func setEventListener(_ eventListener: InAppEventListener?)

    func dismissMessage()
}

public class MessagingInApp: ModuleTopLevelObject<MessagingInAppInstance>, MessagingInAppInstance {
    @Atomic public internal(set) static var shared = MessagingInApp()
    private static let moduleName = "MessagingInApp"

    // constructor that is called by test classes
    // This function's job is to populate the `shared` property with
    // overrides such as DI graph.
    init(implementation: MessagingInAppInstance?) {
        super.init(moduleName: Self.moduleName, implementation: implementation)
    }

    // constructor used in production with default DI graph
    // singleton constructor
    private init() {
        super.init(moduleName: Self.moduleName)
    }

    // for testing
    static func resetSharedInstance() {
        shared = MessagingInApp()
    }

    // MARK: static initialized functions for customers.

    // static functions are identical to initialize functions in InAppInstance protocol to try and make a more convenient
    // API for customers. Customers can use `MessagingInApp.initialize(...)` instead of `MessagingInApp.shared.initialize(...)`.
    // Trying to follow the same API as `CustomerIO` class with `initialize()`.

    /**
     Initialize the shared `instance` of `MessagingInApp`.
     Call this function when your app launches, before using `MessagingInApp.shared`.
     */
    @available(iOSApplicationExtension, unavailable)
    @discardableResult
    public static func initialize(
        siteId: String,
        region: Region,
        configure configureHandler: ((inout MessagingInAppConfigOptions) -> Void)? = nil
    ) -> MessagingInAppInstance {
        var moduleConfig = MessagingInAppConfigOptions.Factory.create(siteId: siteId, region: region)

        if let configureHandler = configureHandler {
            configureHandler(&moduleConfig)
        }

        shared.initializeModule(moduleConfig: moduleConfig)
        return shared
    }

    // Internal initializer for setting up the module with desired values
    private func initializeModule(moduleConfig: MessagingInAppConfigOptions) {
        guard getImplementationInstance() == nil else {
            logger.info("\(moduleName) module is already initialized. Ignoring redundant initialization request.")
            return
        }

        logger.debug("Setting up \(moduleName) module...")
        let inAppImplementation = MessagingInAppImplementation(diGraph: DIGraphShared.shared, moduleConfig: moduleConfig)
        setImplementationInstance(implementation: inAppImplementation)

        // FIXME: [CDP] Update hooks to work as expected
        // Register MessagingPush module hooks now that the module is being initialized.
        // let hooks = diGraph.hooksManager
        // let moduleHookProvider = MessagingInAppModuleHookProvider()
        // hooks.add(key: .messagingInApp, provider: moduleHookProvider)
        logger.info("\(moduleName) module successfully set up with SDK")
    }

    public func setEventListener(_ eventListener: InAppEventListener?) {
        implementation?.setEventListener(eventListener)
    }

    // Dismiss in-app message
    public func dismissMessage() {
        implementation?.dismissMessage()
    }
}
