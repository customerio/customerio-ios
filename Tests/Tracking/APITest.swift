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
class TrackingAPITest: UnitTest {
    let dictionaryData: [String: Any] = ["foo": true, "bar": ""]
    struct EncodableExample: Encodable {
        let foo: String
    }

    let encodableData = EncodableExample(foo: "")

    // Test that public functions are accessible by mocked instances
    let mock = CustomerIOInstanceMock()

    // This function checks that public functions exist for the SDK and they are callable.
    // Maybe we forgot to add a function? Maybe we forgot to make a function `public`?
    func test_allPublicTrackingFunctions() throws {
        try skipRunningTest()

        // Initialize
        CustomerIO.initialize(siteId: "", apiKey: "", region: .EU) { (config: inout CioSdkConfig) in
            config.autoTrackPushEvents = false
        }
        // There is another `initialize()` function that's available to Notification Service Extension and not available
        // to other targets (such as iOS).
        // You should be able to uncomment the initialize() function below and should get compile errors saying that the
        // function is not available to iOS.
        // CustomerIO.initialize(siteId: "", apiKey: "", region: .EU) { (config: inout CioRichPushSdkConfig) in }

        // Reference some objects that should be public in the Tracking module
        let region: Region = .EU
        let loglevel: CioLogLevel = .debug

        // Identify
        CustomerIO.shared.identify(identifier: "")
        mock.identify(identifier: "")
        CustomerIO.shared.identify(identifier: "", body: dictionaryData)
        mock.identify(identifier: "", body: dictionaryData)
        CustomerIO.shared.identify(identifier: "", body: encodableData)
        mock.identify(identifier: "", body: encodableData)

        // clear identify
        CustomerIO.shared.clearIdentify()
        mock.clearIdentify()

        // event tracking
        CustomerIO.shared.track(name: "")
        mock.track(name: "")
        CustomerIO.shared.track(name: "", data: dictionaryData)
        mock.track(name: "", data: dictionaryData)
        CustomerIO.shared.track(name: "", data: encodableData)
        mock.track(name: "", data: encodableData)

        // screen tracking
        CustomerIO.shared.screen(name: "")
        mock.screen(name: "")
        CustomerIO.shared.screen(name: "", data: dictionaryData)
        mock.screen(name: "", data: dictionaryData)
        CustomerIO.shared.screen(name: "", data: encodableData)
        mock.screen(name: "", data: encodableData)

        // register push token
        CustomerIO.shared.registerDeviceToken("")
        mock.registerDeviceToken("")

        // delete push token
        CustomerIO.shared.deleteDeviceToken()
        mock.deleteDeviceToken()

        // track push metric
        let metric = Metric.delivered
        CustomerIO.shared.trackMetric(deliveryID: "", event: metric, deviceToken: "")
        mock.trackMetric(deliveryID: "", event: metric, deviceToken: "")

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

    func test_allPublicSdkConfigOptions() throws {
        try skipRunningTest()

        CustomerIO.initialize(siteId: "", apiKey: "", region: .EU) { config in
            config.trackingApiUrl = ""
            config.autoTrackPushEvents = true
            config.backgroundQueueMinNumberOfTasks = 10
            config.backgroundQueueSecondsDelay = 10
            config.logLevel = .error
            config.autoTrackPushEvents = false
            config.autoScreenViewBody = { [:] }
        }
    }
}
