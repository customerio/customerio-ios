import CioInternalCommon // do not use `@testable` so we can test functions are made public and not `internal`.
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
class CommonAPITest: UnitTest {
    // Test that public functions are accessible by mocked instances
    let mock = CustomerIOInstanceMock()

    func test_allPublicStaticPropertiesAvailable() throws {
        try skipRunningTest()

        _ = CustomerIO.version
    }

    // This function checks that public functions exist for the SDK and they are callable.
    // Maybe we forgot to add a function? Maybe we forgot to make a function `public`?
    func test_allPublicTrackingFunctions() throws {
        try skipRunningTest()

        // Reference some objects that should be public in the Tracking module
        let _: Region = .EU
        let _: CioLogLevel = .debug
    }

    // This function checks that SdkConfig is accessible and can be created using the factory.
    func test_createSdkConfig() {
        // Outside of the Common module, we should be able to create a `SdkConfig` using the factory.
        _ = SdkConfig.Factory.create(logLevel: .debug)
        // Factory method should allow nil values for `SdkConfig` to enable fallback to defaults.
        _ = SdkConfig.Factory.create(logLevel: nil)
        // Wrapper SDKs should be able to create a `SdkConfig` from a dictionary.
        _ = SdkConfig.Factory.create(from: [:])
    }
}
