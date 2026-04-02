@testable import CioInternalCommon
import XCTest

final class AppGroupIdentifierTests: XCTestCase {
    private let expectedGroup = "group.com.example.myapp.cio"

    // MARK: - identifier(forProcessBundleIdentifier:)

    func test_identifier_forProcessBundleIdentifier_whenNil_returnsNil() {
        XCTAssertNil(AppGroupIdentifier.identifier(forProcessBundleIdentifier: nil))
    }

    func test_identifier_forProcessBundleIdentifier_whenEmpty_returnsNil() {
        XCTAssertNil(AppGroupIdentifier.identifier(forProcessBundleIdentifier: "   "))
    }

    func test_identifier_forProcessBundleIdentifier_whenMainApp_returnsExpectedGroup() {
        XCTAssertEqual(
            AppGroupIdentifier.identifier(forProcessBundleIdentifier: "com.example.myapp"),
            expectedGroup
        )
    }

    func test_identifier_forProcessBundleIdentifier_whenPaddedWithWhitespace_trimsAndReturnsGroup() {
        XCTAssertEqual(
            AppGroupIdentifier.identifier(forProcessBundleIdentifier: "  com.example.myapp  "),
            expectedGroup
        )
    }

    func test_identifier_forProcessBundleIdentifier_whenRichPushSuffix_stripsAndReturnsGroup() {
        XCTAssertEqual(
            AppGroupIdentifier.identifier(forProcessBundleIdentifier: "com.example.myapp.richpush"),
            expectedGroup
        )
    }

    func test_identifier_forProcessBundleIdentifier_whenRichPushCamelCaseSuffix_stripsAndReturnsGroup() {
        XCTAssertEqual(
            AppGroupIdentifier.identifier(forProcessBundleIdentifier: "com.example.myapp.richPush"),
            expectedGroup
        )
    }

    func test_identifier_forProcessBundleIdentifier_whenNotificationServiceExtensionSuffix_stripsAndReturnsGroup() {
        XCTAssertEqual(
            AppGroupIdentifier.identifier(forProcessBundleIdentifier: "com.example.myapp.NotificationServiceExtension"),
            expectedGroup
        )
    }

    func test_identifier_forProcessBundleIdentifier_whenNotificationServiceSuffix_stripsAndReturnsGroup() {
        XCTAssertEqual(
            AppGroupIdentifier.identifier(forProcessBundleIdentifier: "com.example.myapp.NotificationService"),
            expectedGroup
        )
    }

    // MARK: - identifier(forMainAppBundleId:)

    func test_identifier_forMainAppBundleId_returnsGroupWithCioSuffix() {
        XCTAssertEqual(
            AppGroupIdentifier.identifier(forMainAppBundleId: "com.example.myapp"),
            expectedGroup
        )
    }

    func test_cioSuffix_isCio() {
        XCTAssertEqual(AppGroupIdentifier.cioSuffix, "cio")
    }
}
