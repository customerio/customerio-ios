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
    struct CodableExample: Codable {
        let foo: String
    }

    let codedData = CodableExample(foo: "")
    let exampleURL = URL(string: "https://example.com")!

    // Test that public functions are accessible by mocked instances
    let mock = CustomerIOInstanceMock()

    // This function checks that public functions exist for the SDK and they are callable.
    // Maybe we forgot to add a function? Maybe we forgot to make a function `public`?
    func test_allPublicTrackingFunctions() throws {
        try skipRunningTest()

        // Initialize
        CustomerIO.initialize(withConfig: SDKConfigBuilder(cdpApiKey: "").build())

        // Identify
        CustomerIO.shared.identify(userId: "")
        mock.identify(userId: "", traits: nil)
        CustomerIO.shared.identify(userId: "", traits: dictionaryData)
        mock.identify(userId: "", traits: dictionaryData)
        CustomerIO.shared.identify(userId: "", traits: codedData)
        mock.identify(userId: "", traits: codedData)

        // clear identify
        CustomerIO.shared.clearIdentify()
        mock.clearIdentify()

        // event tracking
        CustomerIO.shared.track(name: "")
        mock.track(name: "", properties: nil)
        CustomerIO.shared.track(name: "", properties: dictionaryData)
        mock.track(name: "", properties: dictionaryData)
        CustomerIO.shared.track(name: "", properties: codedData)
        mock.track(name: "", properties: codedData)

        // screen tracking
        CustomerIO.shared.screen(title: "")
        mock.screen(title: "", properties: nil)
        CustomerIO.shared.screen(title: "", properties: dictionaryData)
        mock.screen(title: "", properties: dictionaryData)
        CustomerIO.shared.screen(title: "", properties: codedData)
        mock.screen(title: "", properties: codedData)

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

        // profile attributes
        CustomerIO.shared.profileAttributes = dictionaryData
        mock.profileAttributes = dictionaryData

        // device attributes
        CustomerIO.shared.deviceAttributes = dictionaryData
        mock.deviceAttributes = dictionaryData

        // extensions
        CustomerIO.shared.setDebugLogsEnabled()
        CustomerIO.shared.setDebugLogsEnabled(false)

        // plugins
        CustomerIO.shared.apply { (_: Plugin) in }
        CustomerIO.shared.add(plugin: UtilityPluginMock())
        CustomerIO.shared.add { (_: RawEvent?) in nil }
        CustomerIO.shared.add { (_: RawEvent?) in TrackEvent(event: String.random, properties: nil) }
        CustomerIO.shared.remove(plugin: UtilityPluginMock())
        let _: UtilityPluginMock? = CustomerIO.shared.find(pluginType: UtilityPluginMock.self)
        let _: [UtilityPluginMock]? = CustomerIO.shared.findAll(pluginType: UtilityPluginMock.self)
        let _: DestinationPlugin? = CustomerIO.shared.find(key: String.random)

        // segment
        let _: Bool = CustomerIO.shared.enabled
        let _: String = CustomerIO.shared.anonymousId
        let _: String? = CustomerIO.shared.userId
        let _: OperatingMode = CustomerIO.shared.operatingMode
        let _: TimeInterval = CustomerIO.shared.flushInterval
        let _: Int = CustomerIO.shared.flushAt
        let _: [FlushPolicy] = CustomerIO.shared.flushPolicies
        let _: CodableExample? = CustomerIO.shared.traits()
        let _: [String: Any]? = CustomerIO.shared.traits()
        CustomerIO.shared.flush {}
        CustomerIO.shared.reset()
        let _: String = CustomerIO.shared.version()
        let _: Settings? = CustomerIO.shared.settings()
        CustomerIO.shared.manuallyEnableDestination(plugin: DestinationPluginMock())
        let _: Bool = CustomerIO.shared.hasUnsentEvents
        let _: [URL]? = CustomerIO.shared.pendingUploads
        CustomerIO.shared.purgeStorage()
        CustomerIO.shared.purgeStorage(fileURL: exampleURL)
        CustomerIO.shared.waitUntilStarted()
        CustomerIO.shared.openURL(exampleURL)
        CustomerIO.shared.openURL(exampleURL, options: codedData)
        CustomerIO.shared.openURL(exampleURL, options: dictionaryData)
    }

    func test_allPublicModuleConfigOptions() throws {
        try skipRunningTest()

        _ = SDKConfigBuilder(cdpApiKey: "")
            .logLevel(.info)
            .apiHost("")
            .cdnHost("")
            .flushAt(10)
            .flushInterval(10.0)
            .autoAddCustomerIODestination(false)
            .defaultSettings(Settings(writeKey: ""))
            .flushPolicies([])
            .flushQueue(DispatchQueue(label: ""))
            .operatingMode(OperatingMode.asynchronous)
            .trackApplicationLifecycleEvents(true)
            .autoTrackDeviceAttributes(true)
            .siteId("")
            .build()
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
