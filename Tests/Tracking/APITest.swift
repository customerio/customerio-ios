import CioInternalCommon
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
    struct CodableExample: Codable {
        let foo: String
    }

    let codedData = CodableExample(foo: "")

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

        // Public properties exposed to customers
        _ = CustomerIO.shared.siteId
        _ = CustomerIO.shared.config

        // Identify
        CustomerIO.shared.identify(identifier: "")
        mock.identify(identifier: "")
        CustomerIO.shared.identify(identifier: "", body: dictionaryData)
        mock.identify(identifier: "", body: dictionaryData)
        CustomerIO.shared.identify(identifier: "", body: codedData)
        mock.identify(identifier: "", body: codedData)

        // clear identify
        CustomerIO.shared.clearIdentify()
        mock.clearIdentify()

        // event tracking
        CustomerIO.shared.track(name: "")
        mock.track(name: "")
        CustomerIO.shared.track(name: "", data: dictionaryData)
        mock.track(name: "", data: dictionaryData)
        CustomerIO.shared.track(name: "", data: codedData)
        mock.track(name: "", data: codedData)

        // screen tracking
        CustomerIO.shared.screen(name: "")
        mock.screen(name: "")
        CustomerIO.shared.screen(name: "", data: dictionaryData)
        mock.screen(name: "", data: dictionaryData)
        CustomerIO.shared.screen(name: "", data: codedData)
        mock.screen(name: "", data: codedData)

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

    // SDK wrappers can configure the SDK from a Map.
    // This test is in API tests as the String keys of the Map are public and need to not break for the SDK wrappers.
    func test_createSdkConfigFromMap() {
        let trackingApiUrl = String.random
        let autoTrackPushEvents = false
        let backgroundQueueMinNumberOfTasks = 10000
        let backgroundQueueSecondsDelay: TimeInterval = 100000
        let backgroundQueueExpiredSeconds: TimeInterval = 100000
        let logLevel = "info"
        let autoTrackScreenViews = true
        let autoTrackDeviceAttributes = false
        let sdkWrapperSource = "Flutter"
        let sdkWrapperVersion = "1000.33333.4444"

        let givenParamsFromSdkWrapper: [String: Any] = [
            "trackingApiUrl": trackingApiUrl,
            "autoTrackPushEvents": autoTrackPushEvents,
            "backgroundQueueMinNumberOfTasks": backgroundQueueMinNumberOfTasks,
            "backgroundQueueSecondsDelay": backgroundQueueSecondsDelay,
            "backgroundQueueExpiredSeconds": backgroundQueueExpiredSeconds,
            "logLevel": logLevel,
            "autoTrackScreenViews": autoTrackScreenViews,
            "autoTrackDeviceAttributes": autoTrackDeviceAttributes,
            "source": sdkWrapperSource,
            "version": sdkWrapperVersion
        ]

        var actual = CioSdkConfig.Factory.create(siteId: "", apiKey: "", region: .US)
        actual.modify(params: givenParamsFromSdkWrapper)

        XCTAssertEqual(actual.trackingApiUrl, trackingApiUrl)
        XCTAssertEqual(actual.autoTrackPushEvents, autoTrackPushEvents)
        XCTAssertEqual(actual.backgroundQueueMinNumberOfTasks, backgroundQueueMinNumberOfTasks)
        XCTAssertEqual(actual.backgroundQueueSecondsDelay, backgroundQueueSecondsDelay)
        XCTAssertEqual(actual.backgroundQueueExpiredSeconds, backgroundQueueExpiredSeconds)
        XCTAssertEqual(actual.logLevel.rawValue, logLevel)
        XCTAssertEqual(actual.autoTrackScreenViews, autoTrackScreenViews)
        XCTAssertEqual(actual.autoTrackDeviceAttributes, autoTrackDeviceAttributes)
        XCTAssertNotNil(actual._sdkWrapperConfig)
    }

    func test_SdkConfigFromMap_givenWrongKeys_expectDefaults() {
        let trackingApiUrl = String.random
        let autoTrackPushEvents = false
        let backgroundQueueMinNumberOfTasks = 10000
        let backgroundQueueSecondsDelay: TimeInterval = 100000
        let backgroundQueueExpiredSeconds: TimeInterval = 100000
        let logLevel = "info"
        let autoTrackScreenViews = true
        let autoTrackDeviceAttributes = false
        let sdkWrapperSource = "Flutter"
        let sdkWrapperVersion = "1000.33333.4444"

        let givenParamsFromSdkWrapper: [String: Any] = [
            "trackingApiUrlWrong": trackingApiUrl,
            "autoTrackPushEventsWrong": autoTrackPushEvents,
            "backgroundQueueMinNumberOfTasksWrong": backgroundQueueMinNumberOfTasks,
            "backgroundQueueSecondsDelayWrong": backgroundQueueSecondsDelay,
            "backgroundQueueExpiredSecondsWrong": backgroundQueueExpiredSeconds,
            "logLevelWrong": logLevel,
            "autoTrackScreenViewsWrong": autoTrackScreenViews,
            "autoTrackDeviceAttributesWrong": autoTrackDeviceAttributes,
            "sourceWrong": sdkWrapperSource,
            "versionWrong": sdkWrapperVersion
        ]

        var actual = CioSdkConfig.Factory.create(siteId: "", apiKey: "", region: .US)
        actual.modify(params: givenParamsFromSdkWrapper)

        XCTAssertEqual(actual.trackingApiUrl, Region.US.productionTrackingUrl)
        XCTAssertEqual(actual.autoTrackPushEvents, true)
        XCTAssertEqual(actual.backgroundQueueMinNumberOfTasks, 10)
        XCTAssertEqual(actual.backgroundQueueSecondsDelay, 30)
        XCTAssertEqual(actual.backgroundQueueExpiredSeconds, TimeInterval(3 * 86400))
        XCTAssertEqual(actual.logLevel.rawValue, CioLogLevel.error.rawValue)
        XCTAssertEqual(actual.autoTrackScreenViews, false)
        XCTAssertEqual(actual.autoTrackDeviceAttributes, true)
        XCTAssertNil(actual._sdkWrapperConfig)
    }

    func test_SdkConfig_givenNoModification_expectDefaults() {
        let actual = CioSdkConfig.Factory.create(siteId: "", apiKey: "", region: .US)

        XCTAssertEqual(actual.trackingApiUrl, Region.US.productionTrackingUrl)
        XCTAssertEqual(actual.autoTrackPushEvents, true)
        XCTAssertEqual(actual.backgroundQueueMinNumberOfTasks, 10)
        XCTAssertEqual(actual.backgroundQueueSecondsDelay, 30)
        XCTAssertEqual(actual.backgroundQueueExpiredSeconds, TimeInterval(3 * 86400))
        XCTAssertEqual(actual.logLevel.rawValue, CioLogLevel.error.rawValue)
        XCTAssertEqual(actual.autoTrackScreenViews, false)
        XCTAssertEqual(actual.autoTrackDeviceAttributes, true)
        XCTAssertNil(actual._sdkWrapperConfig)
    }
}
