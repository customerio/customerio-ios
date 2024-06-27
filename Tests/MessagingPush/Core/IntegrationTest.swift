@testable import CioInternalCommon
@testable import CioMessagingPush
import Foundation
@testable import SharedTests
import XCTest

/// Extension of `UnitTest` but performs some tasks that sets the environment for integration tests.
/// Unit test classes should have a predictable environment for easier debugging. Integration tests
/// have more SDK code involved and may require some modification to the test environment before tests run.
open class IntegrationTest: UnitTest {
    // Use minimal mocks/stubs in integration tests to closely match production behavior.
    public private(set) var deviceInfoStub: DeviceInfoStub!

    override open func setUpDependencies() {
        super.setUpDependencies()

        // Mock device info since we are running tests, not running the app on a device. Tests crash when trying to
        // execute the code in the real device into implementation.
        deviceInfoStub = DeviceInfoStub()
        diGraphShared.override(value: deviceInfoStub, forType: DeviceInfo.self)
    }

    override open func initializeSDKComponents() -> MessagingPushInstance? {
        // Initialize and configure MessagingPush for testing to closely resemble actual app setup
        MessagingPush.setUpSharedInstanceForIntegrationTest(diGraphShared: diGraphShared, config: messagingPushConfigOptions)

        return MessagingPush.shared
    }

    // Create new mock instance and setup with set of defaults.
    func getNewPushEventHandler() -> PushEventHandlerMock {
        let newInstance = PushEventHandlerMock()
        // We expect that each instance has it's own unique identifier.
        newInstance.underlyingIdentifier = .random
        return newInstance
    }
}
