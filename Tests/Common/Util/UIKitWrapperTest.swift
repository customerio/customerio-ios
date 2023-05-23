@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class UIKitWrpperTest: UnitTest {
    private var uiKit: UIKitWrapperImpl!

    override func setUp() {
        super.setUp()

        uiKit = UIKitWrapperImpl()
    }

    // MARK: continueNSUserActivity

    func test_continueNSUserActivity_givenAppSchemeUrl_expectFalse() {
        let given = URL(string: "remote-habits://switch_workspace?site_id=AAA&api_key=BBB")!

        XCTAssertFalse(uiKit.isLinkValidNSUserActivityLink(given))
    }

    func test_continueNSUserActivity_givenUniversalLinkUrl_expectTrue() {
        let given = URL(string: "https://remotehabits.com/switch_workspace?site_id=AAA&api_key=BBB")!

        XCTAssertTrue(uiKit.isLinkValidNSUserActivityLink(given))
    }
}
