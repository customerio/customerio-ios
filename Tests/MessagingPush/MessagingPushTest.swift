@testable import CioMessagingPush
@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class MessagingPushTest: UnitTest {
    private var mockCustomerIO = CustomerIOInstanceMock()
    private var messagingPush: MessagingPush!

    override func setUp() {
        super.setUp()

        messagingPush = MessagingPush(customerIO: mockCustomerIO)
    }

    // MARK: deinit

    func test_givenNilObject_expectDeinit() {
        let cio = CustomerIO(siteId: String.random, apiKey: String.random)

        var messagingPush: MessagingPush? = MessagingPush(customerIO: cio)

        messagingPush = nil

        XCTAssertNil(messagingPush)
    }
}
