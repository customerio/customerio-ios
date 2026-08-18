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

    func testDoesMatchUniversalLink_givenDifferentPath_thenReturnsFalse() {
        let handler = AppDeepLinksHandlerUtil()

        XCTAssertFalse(handler.doesMatchUniversalLink(URL(string: "https://ciosample.page.link/settings")!))
    }
}
