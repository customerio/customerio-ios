@testable import CioMessagingPush
@testable import CioMessagingPushFCM
@testable import CioTracking
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
    func test_allPublicFunctions() {
        _ = XCTSkip()

        MessagingPush.shared.messaging("", didReceiveRegistrationToken: "token")
        MessagingPush.shared.messaging("", didReceiveRegistrationToken: nil)
    }
}
