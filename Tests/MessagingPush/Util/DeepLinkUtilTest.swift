@testable import CioMessagingPush
import Foundation
import SharedTests
import XCTest

class DeepLinkUtilTest: UnitTest {
    private var deepLinkUtil: DeepLinkUtil!

    override func setUp() {
        super.setUp()

        deepLinkUtil = DeepLinkUtilImpl()
    }

    // MARK: isLinkValidNSUserActivityLink

    func test_isLinkValidNSUserActivityLink_givenAppSchemeUrl_expectFalse() {
        let given = "remote-habits://switch_workspace?site_id=AAA&api_key=BBB"

        XCTAssertFalse(deepLinkUtil.isLinkValidNSUserActivityLink(given))
    }

    func test_isLinkValidNSUserActivityLink_givenUniversalLinkUrl_expectTrue() {
        let given = "https://remotehabits.com/switch_workspace?site_id=AAA&api_key=BBB"

        XCTAssertTrue(deepLinkUtil.isLinkValidNSUserActivityLink(given))
    }
}
