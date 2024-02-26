@testable import CioInternalCommon
@testable import CioMessagingInApp
import SharedTests

/// Base class for unit testing within the module, extending `UnitTestBase` with setup and utilities
/// specific to module components. Ideal for isolated tests of individual functions and classes.
open class UnitTest: SharedTests.UnitTestBase<MessagingInAppInstance> {
    public private(set) var messagingInAppConfigOptions: MessagingInAppConfigOptions!

    override open func setUp() {
        setUp(modifyModuleConfig: nil)
    }

    override open func setUp(enableLogs: Bool = false, sdkConfig: SdkConfig? = nil) {
        setUp(enableLogs: enableLogs, modifyModuleConfig: nil)
    }

    open func setUp(
        enableLogs: Bool = false,
        siteId: String? = nil,
        region: Region = .US,
        modifyModuleConfig: ((MessagingInAppConfigBuilder) -> Void)?
    ) {
        let moduleConfigBuilder = MessagingInAppConfigBuilder(siteId: siteId ?? testSiteId, region: region)
        modifyModuleConfig?(moduleConfigBuilder)
        messagingInAppConfigOptions = moduleConfigBuilder.build()

        super.setUp(enableLogs: enableLogs, sdkConfig: nil)
    }

    override open func initializeSDKComponents() -> MessagingInAppInstance? {
        // Initialize and configure MessagingPush implementation for unit testing
        let implementation = MessagingInAppImplementation(diGraph: diGraphShared, moduleConfig: messagingInAppConfigOptions)
        MessagingInApp.setUpSharedInstanceForUnitTest(implementation: implementation)
        return implementation
    }

    override open func cleanupTestEnvironment() {
        super.cleanupTestEnvironment()
        MessagingInApp.resetTestEnvironment()
    }
}
