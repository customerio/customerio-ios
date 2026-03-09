@testable import CioAnalytics
@testable import CioDataPipelines
@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class IdentifyContextPluginTest: UnitTest {
    func test_identify_addsProviderAttributesToContext() {
        let registry = ProfileEnrichmentRegistryImpl()
        registry.register(StubEnrichmentProviderPluginTest(attributes: [
            "location_latitude": 37.7749,
            "location_longitude": -122.4194
        ]))
        let plugin = IdentifyContextPlugin(registry: registry, logger: log)

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
        let plugin = IdentifyContextPlugin(registry: registry, logger: log)
        var event = IdentifyEvent(userId: "user-1", traits: nil)
        event.context = nil

        let result: IdentifyEvent? = plugin.identify(event: event)

        XCTAssertNotNil(result)
        XCTAssertNil(result?.context?.dictionaryValue?["location_latitude"])
    }

    func test_reset_thenIdentify_doesNotIncludeClearedProviderContext() {
        let statefulProvider = StubStatefulEnrichmentProvider(attributes: [
            "location_latitude": 37.7749,
            "location_longitude": -122.4194
        ])
        let registry = ProfileEnrichmentRegistryImpl()
        registry.register(statefulProvider)
        let plugin = IdentifyContextPlugin(registry: registry, logger: log)

        var eventA = IdentifyEvent(userId: "userA", traits: nil)
        eventA.context = nil
        let resultA: IdentifyEvent? = plugin.identify(event: eventA)
        XCTAssertEqual(resultA?.context?.dictionaryValue?["location_latitude"] as? Double, 37.7749)

        plugin.reset()

        var eventB = IdentifyEvent(userId: "userB", traits: nil)
        eventB.context = nil
        let resultB: IdentifyEvent? = plugin.identify(event: eventB)
        XCTAssertNil(resultB?.context?.dictionaryValue?["location_latitude"], "userB must not get userA's cleared context")
    }
}

private final class StubStatefulEnrichmentProvider: ProfileEnrichmentProvider {
    private var attributes: [String: Any]?

    init(attributes: [String: Any]?) {
        self.attributes = attributes
    }

    func getProfileEnrichmentAttributes() -> [String: Any]? {
        attributes
    }

    func resetContext() {
        attributes = nil
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
