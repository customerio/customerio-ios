// Do not use `@testable` so we can test functions are made public and not `internal`.
import CioFirebaseWrapper
import CioMessagingPushFCM
import Foundation
import XCTest

/**
 Contains an example of every public facing SDK function call added by CioFirebaseWrapper.
 If a public function is modified, this test class will not compile.

 Note: This test is skipped at runtime but must compile to verify the public API.
 */
class CioFirebaseWrapperAPITest: XCTestCase {
    func test_allPublicFunctions() throws {
        try XCTSkipIf(true, "This is a compile-time only test to verify public API signatures")

        MessagingPushFCM.initialize()
        MessagingPushFCM.initialize(withConfig: MessagingPushConfigBuilder().build())
    }
}
