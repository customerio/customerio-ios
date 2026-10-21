@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class ApiKeyTest: UnitTest {
    func test_isSecret_givenSecretKey_expectTrue() {
        XCTAssertTrue(ApiKey.isSecret("ak_us_\(String.random)"))
    }

    func test_isSecret_givenPublicOrLegacyKey_expectFalse() {
        XCTAssertFalse(ApiKey.isSecret("wk_us_\(String.random)"))
        XCTAssertFalse(ApiKey.isSecret(String.random))
    }

    func test_isPublic_givenPublicKey_expectTrue() {
        XCTAssertTrue(ApiKey.isPublic("wk_us_\(String.random)"))
        XCTAssertTrue(ApiKey.isPublic("wk_eu_\(String.random)"))
    }

    func test_isPublic_givenSecretOrLegacyKey_expectFalse() {
        XCTAssertFalse(ApiKey.isPublic("ak_us_\(String.random)"))
        XCTAssertFalse(ApiKey.isPublic("wk_xx_\(String.random)"))
        XCTAssertFalse(ApiKey.isPublic(String.random))
    }

    func test_region_givenPrefixedKey_expectRegionFromKey() {
        XCTAssertEqual(ApiKey.region(of: "wk_eu_\(String.random)"), .EU)
        XCTAssertEqual(ApiKey.region(of: "wk_us_\(String.random)"), .US)
        XCTAssertEqual(ApiKey.region(of: "ak_eu_\(String.random)"), .EU)
    }

    func test_region_givenLegacyKey_expectNil() {
        XCTAssertNil(ApiKey.region(of: String.random))
        XCTAssertNil(ApiKey.region(of: "wk_eu"))
    }
}
