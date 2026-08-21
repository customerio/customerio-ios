@testable import APN_UIKit
import XCTest

final class Tests: XCTestCase {
    func testDoesMatchUniversalLink_givenSupportedHTTPSURL_thenReturnsTrue() {
        let handler = AppDeepLinksHandlerUtil()

        XCTAssertTrue(handler.doesMatchUniversalLink(URL(string: "https://ciosample.page.link/spm")!))
    }

    func testDoesMatchUniversalLink_givenSupportedHTTPURL_thenReturnsTrue() {
        let handler = AppDeepLinksHandlerUtil()

        XCTAssertTrue(handler.doesMatchUniversalLink(URL(string: "http://ciosample.page.link/spm")!))
    }

    func testDoesMatchUniversalLink_givenUppercaseSchemeAndHost_thenReturnsTrue() {
        let handler = AppDeepLinksHandlerUtil()

        XCTAssertTrue(handler.doesMatchUniversalLink(URL(string: "HTTPS://CIOSAMPLE.PAGE.LINK/spm")!))
    }

    func testDoesMatchUniversalLink_givenDifferentHost_thenReturnsFalse() {
        let handler = AppDeepLinksHandlerUtil()

        XCTAssertFalse(handler.doesMatchUniversalLink(URL(string: "https://other.example.com/spm")!))
    }

    func testDoesMatchUniversalLink_givenUnsupportedScheme_thenReturnsFalse() {
        let handler = AppDeepLinksHandlerUtil()

        XCTAssertFalse(handler.doesMatchUniversalLink(URL(string: "apn-uikit://ciosample.page.link/spm")!))
    }

    func testDoesMatchUniversalLink_givenDifferentPath_thenReturnsFalse() {
        let handler = AppDeepLinksHandlerUtil()

        XCTAssertFalse(handler.doesMatchUniversalLink(URL(string: "https://ciosample.page.link/settings")!))
    }
}
