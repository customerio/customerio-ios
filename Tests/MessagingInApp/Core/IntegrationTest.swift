@testable import CioInternalCommon
@testable import CioMessagingInApp
import Foundation
@testable import SharedTests
import XCTest

/// Extension of `UnitTest` but performs some tasks that sets the environment for integration tests.
/// Unit test classes should have a predictable environment for easier debugging. Integration tests
/// have more SDK code involved and may require some modification to the test environment before tests run.
open class IntegrationTest: UnitTest {
    // Use minimal mocks/stubs in integration tests to closely match production behavior.

    var viewAnimationRunnerStub: ViewAnimationRunnerStub!

    override open func initializeSDKComponents() -> MessagingInAppInstance? {
        // Initialize and configure MessagingPush for testing to closely resemble actual app setup
        MessagingInApp.setUpSharedInstanceForIntegrationTest(diGraphShared: diGraphShared, config: messagingInAppConfigOptions)

        viewAnimationRunnerStub = ViewAnimationRunnerStub()

        // Disables UIKit animations to make tests run instantly and synchronously. Making tests faster, easier to write, and more reliable.
        diGraphShared.override(value: viewAnimationRunnerStub, forType: ViewAnimationRunner.self)

        return MessagingInApp.shared
    }
}
