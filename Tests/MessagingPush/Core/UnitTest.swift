@testable import CioInternalCommon
@testable import CioMessagingPush
import SharedTests

/// Base class for unit testing within the module, extending `UnitTestBase` with setup and utilities
/// specific to module components. Ideal for isolated tests of individual functions and classes.
open class UnitTest: SharedTests.UnitTestBase<MessagingPushInstance> {
    public private(set) var messagingPushConfigOptions: MessagingPushConfigOptions!

    override open func setUp() {
        setUp(modifyModuleConfig: nil)
    }

    override open func setUp(enableLogs: Bool = false, sdkConfig: SdkConfig? = nil) {
        setUp(enableLogs: enableLogs, modifyModuleConfig: nil)
    }

    open func setUp(
        enableLogs: Bool = false,
        modifyModuleConfig: ((MessagingPushConfigBuilder) -> Void)?
    ) {
        let moduleConfigBuilder = MessagingPushConfigBuilder()
        modifyModuleConfig?(moduleConfigBuilder)
        messagingPushConfigOptions = moduleConfigBuilder.build()

        super.setUp(enableLogs: enableLogs, sdkConfig: nil)
    }

    override open func initializeSDKComponents() -> MessagingPushInstance? {
        // Initialize and configure MessagingPush implementation for unit testing
        let implementation = MessagingPushImplementation(diGraph: diGraphShared, moduleConfig: messagingPushConfigOptions)
        MessagingPush.setUpSharedInstanceForUnitTest(implementation: implementation, diGraphShared: diGraphShared, config: messagingPushConfigOptions)
        return implementation
    }

    override open func cleanupTestEnvironment() {
        super.cleanupTestEnvironment()
        MessagingPush.resetTestEnvironment()
    }
}
