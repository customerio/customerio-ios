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

    /// Sets up the module with `moduleConfig` as given, so a test can use options that `MessagingPushConfigBuilder`
    /// only sets from app extensions without marking the test itself `@available(iOS, unavailable)`.
    open func setUp(enableLogs: Bool = false, moduleConfig: MessagingPushConfigOptions) {
        messagingPushConfigOptions = moduleConfig

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

public extension MessagingPushConfigOptions {
    /// Builder defaults with `apiHost` and `region` set, for tests that don't call the extension-only builder methods.
    static func withApiHost(_ apiHost: String?, region: Region = .US) -> MessagingPushConfigOptions {
        let defaults = MessagingPushConfigBuilder().build()
        return MessagingPushConfigOptions(
            logLevel: defaults.logLevel,
            cdpApiKey: defaults.cdpApiKey,
            region: region,
            autoFetchDeviceToken: defaults.autoFetchDeviceToken,
            autoTrackPushEvents: defaults.autoTrackPushEvents,
            showPushAppInForeground: defaults.showPushAppInForeground,
            appGroupId: defaults.appGroupId,
            apiHost: apiHost
        )
    }
}
