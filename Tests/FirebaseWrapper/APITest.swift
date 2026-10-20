// Moved from customerio/customerio-ios-fcm (Tests/APITest.swift). Compiled only with the FCM trait.
#if FCM
// Do not use `@testable` so we can test functions are made public and not `internal`.
import CioFirebaseWrapper
import CioMessagingPushFCM
import Foundation
import XCTest

/**
 Contains an example of every public facing SDK function call added by CioFirebaseWrapper.
 This file helps us prevent introducing breaking changes to the SDK by accident. If a public
 function of the SDK is modified, this test class will not successfully compile. By not compiling,
 that is a reminder to either fix the compilation and introduce the breaking change or fix the
 mistake and not introduce the breaking change in the code base.

 Note: This test is skipped at runtime but must compile to verify the public API.
 */
class CioFirebaseWrapperAPITest: XCTestCase {
    func test_allPublicFunctions() throws {
        // Skip actually running the test - we only care that it compiles
        try XCTSkipIf(true, "This is a compile-time only test to verify public API signatures")

        // Test that MessagingPushFCM.initialize() is accessible through the CioFirebaseWrapper extension
        // Config is optional because MessagingPushConfigOptions does not have any required fields.
        // Providing default value for config makes it easier for customers to initialize MessagingPushFCM module.
        MessagingPushFCM.initialize()
        MessagingPushFCM.initialize(withConfig: MessagingPushConfigBuilder().build())
    }
}
#endif
