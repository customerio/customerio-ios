import CioAnalytics
import CioDataPipelines // do not use `@testable` so we can test functions are made public and not `internal`.
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
class DataPipelineAPITest: UnitTest {
    let dictionaryData: [String: Any] = ["foo": true, "bar": ""]
    struct CodableExample: Codable {
        let foo: String
    }

    let codedData = CodableExample(foo: "")
    let exampleURL = URL(string: "https://example.com")!

    // This function checks that public functions exist for the SDK and they are callable.
    // Maybe we forgot to add a function? Maybe we forgot to make a function `public`?
    func test_allPublicFunctions() throws {
        try skipRunningTest()

        // Initialize
        CustomerIO.initialize(withConfig: SDKConfigBuilder(cdpApiKey: .random).build())

        // Identify
        CustomerIO.shared.identify(userId: "")
        CustomerIO.shared.identify(userId: "", traits: dictionaryData)
        CustomerIO.shared.identify(userId: "", traits: codedData)

        // clear identify
        CustomerIO.shared.clearIdentify()

        // event tracking
        CustomerIO.shared.track(name: "")
        CustomerIO.shared.track(name: "", properties: dictionaryData)
        CustomerIO.shared.track(name: "", properties: codedData)

        // screen tracking
        CustomerIO.shared.screen(title: "")
        CustomerIO.shared.screen(title: "", properties: dictionaryData)
        CustomerIO.shared.screen(title: "", properties: codedData)

        // register push token
        CustomerIO.shared.registerDeviceToken("")

        // delete push token
        CustomerIO.shared.deleteDeviceToken()

        // track push metric
        let metric = Metric.delivered
        CustomerIO.shared.trackMetric(deliveryID: "", event: metric, deviceToken: "")

        // profile attributes
        CustomerIO.shared.profileAttributes = dictionaryData

        // device attributes
        CustomerIO.shared.deviceAttributes = dictionaryData

        // plugins
        CustomerIO.shared.apply { (_: Plugin) in }
        CustomerIO.shared.add(plugin: UtilityPluginMock())
        CustomerIO.shared.add { (_: RawEvent?) in nil }
        CustomerIO.shared.add { (_: RawEvent?) in TrackEvent(event: String.random, properties: nil) }
        CustomerIO.shared.remove(plugin: UtilityPluginMock())
        let _: UtilityPluginMock? = CustomerIO.shared.find(pluginType: UtilityPluginMock.self)
        let _: [UtilityPluginMock]? = CustomerIO.shared.findAll(pluginType: UtilityPluginMock.self)
        let _: DestinationPlugin? = CustomerIO.shared.find(key: String.random)
    }

    func test_segmentPublicFunctions() throws {
        // segment
        let _: Bool = CustomerIO.shared.enabled
        let _: String = CustomerIO.shared.anonymousId
        let _: String? = CustomerIO.shared.userId
        CustomerIO.shared.flush {}
        CustomerIO.shared.reset()
        let _: Bool = CustomerIO.shared.hasUnsentEvents
        let _: [URL]? = CustomerIO.shared.pendingUploads
        CustomerIO.shared.purgeStorage()
        CustomerIO.shared.purgeStorage(fileURL: exampleURL)
        CustomerIO.shared.waitUntilStarted()
    }

    func test_allPublicModuleConfigOptions() throws {
        try skipRunningTest()

        _ = SDKConfigBuilder(cdpApiKey: .random)
            .region(Region.US)
            .logLevel(.info)
            .apiHost("")
            .cdnHost("")
            .flushAt(10)
            .flushInterval(10.0)
            .flushPolicies([])
            .trackApplicationLifecycleEvents(true)
            .autoTrackDeviceAttributes(true)
            .migrationSiteId("")
            .build()
    }

    func test_autoTrackingScreenViewsPluginOptions() throws {
        try skipRunningTest()

        _ = AutoTrackingScreenViews(
            filterAutoScreenViewEvents: { viewController in
                class MyViewController: UIViewController {}

                return viewController is MyViewController
            },
            autoScreenViewBody: { self.dictionaryData }
        )
    }
}
