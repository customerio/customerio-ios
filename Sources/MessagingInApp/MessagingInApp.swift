import CioInternalCommon
import Foundation

public protocol MessagingInAppInstance: AutoMockable {
    /// Access to the message inbox functionality.
    var inbox: NotificationInbox { get }

    // sourcery:Name=setEventListener
    func setEventListener(_ eventListener: InAppEventListener?)

    // sourcery:Name=setInboxEventListener
    func setInboxEventListener(_ inboxEventListener: InboxEventListener?)

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

    /// Access to the message inbox functionality.
    ///
    /// - Important: You must call `MessagingInApp.initialize(withConfig:)` before accessing this property.
    public var inbox: NotificationInbox {
        implementation?.inbox ?? NoOpNotificationInbox()
    }

    public func setEventListener(_ eventListener: InAppEventListener?) {
        implementation?.setEventListener(eventListener)
    }

    /// Registers a listener notified when the user takes an action on a Visual Notification Inbox
    /// message. The listener can intercept the action (return `true`) to suppress the SDK's default
    /// navigation. See ``InboxEventListener``.
    public func setInboxEventListener(_ inboxEventListener: InboxEventListener?) {
        implementation?.setInboxEventListener(inboxEventListener)
    }

    // Dismiss in-app message
    public func dismissMessage() {
        implementation?.dismissMessage()
    }
}
