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
    // Test that all public functions are accessible by non-singleton instances
    var instance: CustomerIOInstance = CustomerIO(siteId: "", apiKey: "")

    // This function checks that public functions exist for the SDK and they are callable.
    // Maybe we forgot to add a function? Maybe we forgot to make a function `public`?
    func test_allPublicTrackingFunctions() throws {
        try skipRunningTest()

        // Initialize
        CustomerIO.initialize(siteId: "", apiKey: "")
        CustomerIO.initialize(siteId: "", apiKey: "", region: .EU)

        // config
        CustomerIO.config { _ in }
        mock.config { _ in }
        instance.config { _ in }

        // Identify
        CustomerIO.shared.identify(identifier: "")
        mock.identify(identifier: "")
        instance.identify(identifier: "")
        CustomerIO.shared.identify(identifier: "", body: dictionaryData)
        mock.identify(identifier: "", body: dictionaryData)
        instance.identify(identifier: "", body: dictionaryData)
        CustomerIO.shared.identify(identifier: "", body: encodableData)
        mock.identify(identifier: "", body: encodableData)
        instance.identify(identifier: "", body: encodableData)

        // clear identify
        CustomerIO.shared.clearIdentify()
        mock.clearIdentify()
        instance.clearIdentify()

        // event tracking
        CustomerIO.shared.track(name: "")
        mock.track(name: "")
        instance.track(name: "")
        CustomerIO.shared.track(name: "", data: dictionaryData)
        mock.track(name: "", data: dictionaryData)
        instance.track(name: "", data: dictionaryData)
        CustomerIO.shared.track(name: "", data: encodableData)
        mock.track(name: "", data: encodableData)
        instance.track(name: "", data: encodableData)

        // screen tracking
        CustomerIO.shared.screen(name: "")
        mock.screen(name: "")
        instance.screen(name: "")
        CustomerIO.shared.screen(name: "", data: dictionaryData)
        mock.screen(name: "", data: dictionaryData)
        instance.screen(name: "", data: dictionaryData)
        CustomerIO.shared.screen(name: "", data: encodableData)
        mock.screen(name: "", data: encodableData)
        instance.screen(name: "", data: encodableData)

        // profile attributes
        CustomerIO.shared.profileAttributes = dictionaryData
        mock.profileAttributes = dictionaryData
        instance.profileAttributes = dictionaryData

        // device attributes
        CustomerIO.shared.deviceAttributes = dictionaryData
        mock.deviceAttributes = dictionaryData
        instance.deviceAttributes = dictionaryData
    }

    func test_allPublicSdkConfigOptions() throws {
        try skipRunningTest()

        CustomerIO.config {
            $0.trackingApiUrl = ""
            $0.autoTrackPushEvents = true
            $0.backgroundQueueMinNumberOfTasks = 10
            $0.backgroundQueueSecondsDelay = 10
            $0.logLevel = .error
            $0.autoTrackPushEvents = false
            $0.autoScreenViewBody = { [:] }
        }
    }
}
