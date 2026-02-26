@testable import CioAnalytics
@testable import CioDataPipelines
@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class ProfileEnrichmentPluginTest: UnitTest {
    func test_identify_addsProviderAttributesToContext() {
        let registry = ProfileEnrichmentRegistryImpl()
        registry.register(StubEnrichmentProviderPluginTest(attributes: [
            "location_latitude": 37.7749,
            "location_longitude": -122.4194
        ]))
        let plugin = ProfileEnrichmentPlugin(registry: registry, logger: log)

        var event = IdentifyEvent(userId: "user-1", traits: nil)
        event.context = nil

        let result: IdentifyEvent? = plugin.identify(event: event)

        XCTAssertNotNil(result)
        let context = result?.context?.dictionaryValue
        XCTAssertEqual(context?["location_latitude"] as? Double, 37.7749)
        XCTAssertEqual(context?["location_longitude"] as? Double, -122.4194)
    }

    func test_identify_emptyEnrichment_returnsEventUnchanged() {
        let registry = ProfileEnrichmentRegistryImpl()
        let plugin = ProfileEnrichmentPlugin(registry: registry, logger: log)
        var event = IdentifyEvent(userId: "user-1", traits: nil)
        event.context = nil

        let result: IdentifyEvent? = plugin.identify(event: event)

        XCTAssertNotNil(result)
        XCTAssertNil(result?.context?.dictionaryValue?["location_latitude"])
    }
}

private final class StubEnrichmentProviderPluginTest: ProfileEnrichmentProvider {
    let attributes: [String: Any]?
    init(attributes: [String: Any]?) {
        self.attributes = attributes
    }

    func getProfileEnrichmentAttributes() -> [String: Any]? {
        attributes
    }
}
