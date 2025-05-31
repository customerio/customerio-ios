import CioInternalCommon
import Foundation

public protocol MessagingInAppInstance: AutoMockable {
    // sourcery:Name=setEventListener
    func setEventListener(_ eventListener: InAppEventListener?)

    func dismissMessage()

    func pauseMessageFetching()

    func resumeMessageFetching()
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

    #if DEBUG
    // Methods to set up the test environment.
    // In unit tests, any implementation of the interface works, while integration tests use the actual implementation.

    @discardableResult
    static func setUpSharedInstanceForUnitTest(implementation: MessagingInAppInstance) -> MessagingInAppInstance {
        shared._implementation = implementation
        return implementation
    }

    @discardableResult
    static func setUpSharedInstanceForIntegrationTest(diGraphShared: DIGraphShared, config: MessagingInAppConfigOptions) -> MessagingInAppInstance {
        let implementation = MessagingInAppImplementation(diGraph: diGraphShared, moduleConfig: config)
        return setUpSharedInstanceForUnitTest(implementation: implementation)
    }

    static func resetTestEnvironment() {
        shared = MessagingInApp()
    }
    #endif

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
    public static func initialize(withConfig config: MessagingInAppConfigOptions) -> MessagingInAppInstance {
        shared.initializeModuleIfNotAlready {
            MessagingInAppImplementation(diGraph: DIGraphShared.shared, moduleConfig: config)
        }

        return shared
    }

    public func setEventListener(_ eventListener: InAppEventListener?) {
        implementation?.setEventListener(eventListener)
    }

    // Dismiss in-app message
    public func dismissMessage() {
        implementation?.dismissMessage()
    }

    /// Pauses message fetching. The polling timer continues running but network requests
    /// for new messages are suspended until message fetching is resumed. Messages already
    /// in the queue will continue to be displayed.
    public func pauseMessageFetching() {
        implementation?.pauseMessageFetching()
    }

    /// Resumes message fetching. If message fetching was previously paused,
    /// this will restart the periodic fetching of new messages from the server.
    public func resumeMessageFetching() {
        implementation?.resumeMessageFetching()
    }
}
