@testable import CioDataPipelines
@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class ProfileEnrichmentAttributesMergerTests: UnitTest {
    private func makeRegistry(providers: [ProfileEnrichmentProvider]) -> ProfileEnrichmentRegistry {
        let registry = ProfileEnrichmentRegistryImpl()
        for provider in providers {
            registry.register(provider)
        }
        return registry
    }

    func test_gatherEnrichmentAttributes_emptyRegistry_returnsEmpty() {
        let registry = makeRegistry(providers: [])
        let result = ProfileEnrichmentAttributesMerger.gatherEnrichmentAttributes(registry: registry)
        XCTAssertTrue(result.isEmpty)
    }

    func test_gatherEnrichmentAttributes_onlyPrimitivesIncluded_nonPrimitivesDropped() {
        let provider = StubProfileEnrichmentProviderForMerger(attributes: [
            "str": "a",
            "bool": true,
            "int": 42,
            "double": 3.14,
            "nested": ["nested": "dict"],
            "array": [1, 2, 3]
        ])
        let registry = makeRegistry(providers: [provider])
        let result = ProfileEnrichmentAttributesMerger.gatherEnrichmentAttributes(registry: registry)
        XCTAssertEqual(result["str"] as? String, "a")
        XCTAssertEqual(result["bool"] as? Bool, true)
        XCTAssertEqual(result["int"] as? Int, 42)
        XCTAssertEqual(result["double"] as? Double, 3.14)
        XCTAssertNil(result["nested"])
        XCTAssertNil(result["array"])
        XCTAssertEqual(result.count, 4)
    }

    func test_gatherEnrichmentAttributes_multipleProviders_allMerged() {
        let p1 = StubProfileEnrichmentProviderForMerger(attributes: ["a": 1, "b": "two"])
        let p2 = StubProfileEnrichmentProviderForMerger(attributes: ["c": 3.0, "d": false])
        let registry = makeRegistry(providers: [p1, p2])
        let result = ProfileEnrichmentAttributesMerger.gatherEnrichmentAttributes(registry: registry)
        XCTAssertEqual(result["a"] as? Int, 1)
        XCTAssertEqual(result["b"] as? String, "two")
        XCTAssertEqual(result["c"] as? Double, 3.0)
        XCTAssertEqual(result["d"] as? Bool, false)
        XCTAssertEqual(result.count, 4)
    }
}

private final class StubProfileEnrichmentProviderForMerger: ProfileEnrichmentProvider {
    let attributes: [String: Any]?
    init(attributes: [String: Any]?) {
        self.attributes = attributes
    }

    func getProfileEnrichmentAttributes() -> [String: Any]? {
        attributes
    }
}
