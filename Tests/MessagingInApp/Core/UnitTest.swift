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

    override open func setUp(enableLogs: Bool = false, siteId: String? = nil, modifySdkConfig: ((inout SdkConfig) -> Void)?) {
        setUp(enableLogs: enableLogs, siteId: siteId, modifySdkConfig: modifySdkConfig, modifyModuleConfig: nil)
    }

    open func setUp(
        enableLogs: Bool = false,
        siteId: String? = nil,
        region: Region = .US,
        modifySdkConfig: ((inout SdkConfig) -> Void)? = nil,
        modifyModuleConfig: ((inout MessagingInAppConfigOptions) -> Void)?
    ) {
        var newConfig = MessagingInAppConfigOptions.Factory.create(siteId: siteId ?? testSiteId, region: region)
        modifyModuleConfig?(&newConfig)
        messagingInAppConfigOptions = newConfig

        super.setUp(enableLogs: enableLogs, siteId: siteId, modifySdkConfig: modifySdkConfig)
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
