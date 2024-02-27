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

class TrackingAPITest: UnitTest {
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

    // SDK wrappers can configure the SDK from a Map.
    // This test is in API tests as the String keys of the Map are public and need to not break for the SDK wrappers.
    func test_createSdkConfigFromMap() {
        let logLevel = "info"

        let givenParamsFromSdkWrapper: [String: Any] = [
            "logLevel": logLevel
        ]

        var actual = SdkConfig.Factory.create()
        actual.modify(params: givenParamsFromSdkWrapper)

        XCTAssertEqual(actual.logLevel.rawValue, logLevel)
    }

    func test_SdkConfigFromMap_givenWrongKeys_expectDefaults() {
        let logLevel = "info"
        let givenParamsFromSdkWrapper: [String: Any] = [
            "logLevelWrong": logLevel
        ]

        var actual = SdkConfig.Factory.create()
        actual.modify(params: givenParamsFromSdkWrapper)

        XCTAssertEqual(actual.logLevel.rawValue, CioLogLevel.error.rawValue)
    }

    func test_SdkConfig_givenNoModification_expectDefaults() {
        let actual = SdkConfig.Factory.create()

        XCTAssertEqual(actual.logLevel.rawValue, CioLogLevel.error.rawValue)
    }
}
