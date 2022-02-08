import CioMessagingPush // do not import so we can test that customers do not need to import this.
import CioMessagingPushFCM // do not use `@testable` so we can test functions are made public and not `internal`.
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
class MessagingPushFCMAPITest: UnitTest {
    // Test that public functions are accessible by mocked instances
    let mock = MessagingPushFCMInstanceMock()

//    let instance: MessagingPushFCMInstance = MessagingPUshFCM()

    func test_allPublicFunctions() throws {
        try skipRunningTest()

        MessagingPush.shared.messaging("", didReceiveRegistrationToken: "token")
        mock.messaging("", didReceiveRegistrationToken: "token")

        MessagingPush.shared.messaging("", didReceiveRegistrationToken: nil)
        mock.messaging("", didReceiveRegistrationToken: nil)
    }
}
