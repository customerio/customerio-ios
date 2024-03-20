@testable import CioInternalCommon
@testable import CioMessagingPush
import Foundation
import SharedTests
import XCTest

class MessagingPushTest: IntegrationTest {
    override func initializeSDKComponents() -> MessagingPushInstance? {
        // We want to manually initialize the module in test functions. So, override this function to disable automatic module initialization.
        nil
    }

    private let automaticPushClickHandlingMock = AutomaticPushClickHandlingMock()

    override func setUp() {
        super.setUp()

        DIGraphShared.shared.override(value: automaticPushClickHandlingMock, forType: AutomaticPushClickHandling.self)
    }

    // MARK: initialize

    func test_initialize_givenDefaultModuleConfigOptions_expectStartAutoPushClickHandling() {
        MessagingPush.initialize()

        XCTAssertEqual(automaticPushClickHandlingMock.startCallsCount, 1)
    }

    func test_initialize_givenCustomerDisabledAutoPushClickHandling_expectDoNotEnableFeature() {
        MessagingPush.initialize(
            withConfig: MessagingPushConfigBuilder()
                .autoTrackPushEvents(false)
                .build()
        )

        XCTAssertFalse(automaticPushClickHandlingMock.startCalled)
    }
}
