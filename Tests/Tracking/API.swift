@testable import CioTracking
import Foundation
import SharedTests
import XCTest

/**
 Contains an example of every public facing SDK function call. This file helps
 us prevent introducing breaking changes to the SDK by accident. If a public function
 of the SDK is modified, this test class will not successfully compile. By not compiling,
 that is a reminder to either fix the comilation and introduce the breaking change or
 fix the mistake and not introduce the breaking change in the code base.
 */
class TrackingAPITest: UnitTest {
    let dictionaryData: [String: Any] = ["foo": true, "bar": ""]
    struct EncodableExample: Encodable {
        let foo: String
    }

    let encodableData = EncodableExample(foo: "")

    func test_allPublicTrackingFunctions() {
        _ = XCTSkip()

        // Initialize
        CustomerIO.initialize(siteId: "", apiKey: "")
        CustomerIO.initialize(siteId: "", apiKey: "", region: .EU)

        // config
        CustomerIO.config { config in }

        // Identify
        CustomerIO.shared.identify(identifier: "")
        // TO FIX: we don't offer a [String: Any] version of identify()
        // CustomerIO.shared.identify(identifier: "", body: dictionaryData)
        CustomerIO.shared.identify(identifier: "", body: encodableData)

        // clear identify
        CustomerIO.shared.clearIdentify()

        // event tracking
        CustomerIO.shared.track(name: "")
        // TO FIX: we don't offer a [String: Any] version of track()
        // CustomerIO.shared.track(name: "", data: dictionaryData)
        CustomerIO.shared.track(name: "", data: encodableData)

        // screen tracking
        CustomerIO.shared.screen(name: "")
        CustomerIO.shared.screen(name: "", data: dictionaryData)
        CustomerIO.shared.screen(name: "", data: encodableData)

        // profile attributes
        CustomerIO.shared.profileAttributes = dictionaryData
    }
}
