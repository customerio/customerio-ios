@testable import CioMessagingPush
@testable import CioTracking
@testable import Common
import Foundation
import SharedTests
import XCTest

class MessagingPushImplementationTest: UnitTest {
    private var mockCustomerIO = CustomerIOInstanceMock()
    private var messagingPush: MessagingPushImplementation!

    private let queueMock = QueueMock()
    private let sdkInitializedUtilMock = SdkInitializedUtilMock()

    override func setUp() {
        super.setUp()

        mockCustomerIO.siteId = testSiteId
        messagingPush = MessagingPushImplementation(
            siteId: testSiteId,
            logger: log,
            jsonAdapter: jsonAdapter,
            sdkConfig: sdkConfig,
            backgroundQueue: queueMock,
            sdkInitializedUtil: sdkInitializedUtilMock
        )
    }
}
