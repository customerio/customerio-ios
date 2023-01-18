import CioMessagingInApp // do not use `@testable` so we can test functions are made public and not `internal`.
import CioTracking // do not use `@testable` so we can test functions are made public and not `internal`.
import Foundation
import SharedTests
import XCTest

/**
 Contains an example of every public facing SDK function call. This file helps
 us prevent introducing breaking changes to the SDK by accident. If a public function
 of the SDK is modified, this test class will not successfully compile. By not compiling,
 that is a reminder to either fix the compilation and introduce the breaking change or
 fix the mistake and not introduce the breaking change in the code base.
 */
class MessagingInAppAPITest: UnitTest {
    // Test that public functions are accessible by mocked instances
    let mock = MessagingInAppInstanceMock()

    func test_allPublicFunctions() throws {
        try skipRunningTest()

        MessagingInApp.initialize(organizationId: "")
        MessagingInApp.initialize(organizationId: "", eventListener: self)
        mock.initialize(organizationId: "")
        mock.initialize(organizationId: "", eventListener: self)
    }
}

extension MessagingInAppAPITest: InAppEventListener {
    func messageShown(message: InAppMessage) {
        // make sure all properties of InAppMessage are accessible
        _ = message.instanceId
        _ = message.messageId
        _ = message.deliveryId
    }

    func messageDismissed(message: InAppMessage) {}

    func errorWithMessage(message: InAppMessage) {}

    func messageActionTaken(message: InAppMessage, currentRoute: String, action: String, name: String) {}
}
