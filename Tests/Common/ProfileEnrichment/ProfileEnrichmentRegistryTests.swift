@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class ProfileEnrichmentRegistryTests: UnitTest {
    func testRegister_andGetAll_returnsAllProviders() {
        let registry = ProfileEnrichmentRegistryImpl()
        XCTAssertTrue(registry.getAll().isEmpty)

        let provider1 = StubProfileEnrichmentProvider(attributes: ["a": 1])
        registry.register(provider1)
        XCTAssertEqual(registry.getAll().count, 1)

        let provider2 = StubProfileEnrichmentProvider(attributes: ["b": "two"])
        registry.register(provider2)
        let all = registry.getAll()
        XCTAssertEqual(all.count, 2)
        XCTAssertTrue(all.contains { ($0 as? StubProfileEnrichmentProvider)?.attributes?["a"] as? Int == 1 })
        XCTAssertTrue(all.contains { ($0 as? StubProfileEnrichmentProvider)?.attributes?["b"] as? String == "two" })
    }
}

/// Stub provider for tests.
final class StubProfileEnrichmentProvider: ProfileEnrichmentProvider {
    let attributes: [String: Any]?

    init(attributes: [String: Any]?) {
        self.attributes = attributes
    }

    func getProfileEnrichmentAttributes() -> [String: Any]? {
        attributes
    }
}
