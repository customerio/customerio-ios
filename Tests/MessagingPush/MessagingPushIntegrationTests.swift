import CioMessagingPush
@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class MessagingPushIntegrationTests: IntegrationTest {
    // In Swift, when you are using `.abc = X` syntax, you are said to be modifying an object.
    // During QA, we have found app crashes caused by SDK where the CustomerIO shared instance is being modified and
    // during that SDK call, some code in the stack *also* refers to `CustomerIO.shared` (trying to read while the
    // modify/write is happening).
    // Test exists in non-tracking module because non-tracking modules are what read CustomerIO.shared in their
    // code-bases which causes the SDK crashes.
    func test_modifyingCustomerIO_expectNoError() {
        CustomerIO.shared.deviceAttributes = [
            "foo": "bar"
        ]
    }
}
