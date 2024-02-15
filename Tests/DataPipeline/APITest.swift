import CioDataPipelines // do not use `@testable` so we can test functions are made public and not `internal`.
import CioInternalCommon
import Foundation
import Segment
import SharedTests
import XCTest

/**
 Contains an example of every public facing SDK function call. This file helps
 us prevent introducing breaking changes to the SDK by accident. If a public function
 of the SDK is modified, this test class will not successfully compile. By not compiling,
 that is a reminder to either fix the compilation and introduce the breaking change or
 fix the mistake and not introduce the breaking change in the code base.
 */
class DataPipelineAPITest: UnitTest {
    let dictionaryData: [String: Any] = ["foo": true, "bar": ""]

    // Test that public functions are accessible by mocked instances
    let mock = CustomerIOInstanceMock()

    // This function checks that public functions exist for the SDK and they are callable.
    // Maybe we forgot to add a function? Maybe we forgot to make a function `public`?
    func test_allPublicTrackingFunctions() throws {
        try skipRunningTest()

        // Initialize
        CustomerIO.initialize(writeKey: "") { (config: inout DataPipelineConfigOptions) in
            config.autoAddCustomerIODestination = false
        }
        CustomerIO.initialize(writeKey: "", logLevel: .debug) { (config: inout DataPipelineConfigOptions) in
            config.autoAddCustomerIODestination = false
        }

        checkDeviceProfileAttributes()
    }

    func checkDeviceProfileAttributes() {
        // profile attributes
        CustomerIO.shared.profileAttributes = dictionaryData
        mock.profileAttributes = dictionaryData

        // device attributes
        CustomerIO.shared.deviceAttributes = dictionaryData
        mock.deviceAttributes = dictionaryData
    }

    func test_allPublicModuleConfigOptions() throws {
        try skipRunningTest()

        CustomerIO.initialize(writeKey: "", logLevel: .error) { config in
            config.apiHost = ""
            config.cdnHost = ""
            config.flushAt = 10
            config.flushInterval = 10.0
            config.autoAddCustomerIODestination = false
            config.defaultSettings = Settings(writeKey: "")
            config.flushPolicies = [CountBasedFlushPolicy(), IntervalBasedFlushPolicy()]
            config.flushQueue = DispatchQueue(label: "")
            config.operatingMode = OperatingMode.asynchronous
            config.trackApplicationLifecycleEvents = true
            config.autoTrackDeviceAttributes = true
        }
    }

    func test_autoTrackingScreenViewsPluginOptions() throws {
        try skipRunningTest()

        _ = AutoTrackingScreenViews(
            filterAutoScreenViewEvents: { viewController in
                class MyViewController: UIViewController {}

                return viewController is MyViewController
            },
            autoScreenViewBody: { [:] }
        )
    }
}
