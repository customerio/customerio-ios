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

    func testHandleAppSchemeDeepLink_givenForeignScheme_thenReturnsFalse() {
        let handler = AppDeepLinksHandlerUtil(storage: StorageManagerStub())

        XCTAssertFalse(handler.handleAppSchemeDeepLink(URL(string: "mailto:support@example.com")!))
    }

    func testHandleAppSchemeDeepLink_givenUnhandledAppRoute_thenReturnsFalse() {
        let handler = AppDeepLinksHandlerUtil(storage: StorageManagerStub())

        XCTAssertFalse(handler.handleAppSchemeDeepLink(URL(string: "apn-uikit://live-activities")!))
    }

    func testHandleAppSchemeDeepLink_givenLoggedInSettingsRoute_thenPostsDashboardRoute() {
        let storage = StorageManagerStub()
        storage.userEmailId = "test@example.com"
        let notificationCenter = NotificationCenter()
        let notificationExpectation = expectation(description: "Dashboard settings route posted")
        let observer = notificationCenter.addObserver(
            forName: .showSettingsScreenOnDashboard,
            object: nil,
            queue: .main
        ) { notification in
            XCTAssertEqual(notification.userInfo?["site_id"] as? String, "test")
            notificationExpectation.fulfill()
        }
        defer { notificationCenter.removeObserver(observer) }
        let handler = AppDeepLinksHandlerUtil(storage: storage, notificationCenter: notificationCenter)

        XCTAssertTrue(handler.handleAppSchemeDeepLink(URL(string: "apn-uikit://settings?site_id=test")!))
        wait(for: [notificationExpectation], timeout: 1)
    }

    func testHandleAppSchemeDeepLink_givenLoggedOutSettingsRoute_thenPostsLoginRoute() {
        let storage = StorageManagerStub()
        let notificationCenter = NotificationCenter()
        let notificationExpectation = expectation(description: "Login settings route posted")
        let observer = notificationCenter.addObserver(
            forName: .showSettingsScreenOnLogin,
            object: nil,
            queue: .main
        ) { _ in
            notificationExpectation.fulfill()
        }
        defer { notificationCenter.removeObserver(observer) }
        let handler = AppDeepLinksHandlerUtil(storage: storage, notificationCenter: notificationCenter)

        XCTAssertTrue(handler.handleAppSchemeDeepLink(URL(string: "apn-uikit://settings")!))
        wait(for: [notificationExpectation], timeout: 1)
    }

    func testHandleUniversalLinkDeepLink_givenNonMatchingLink_thenReturnsFalse() {
        let handler = AppDeepLinksHandlerUtil()

        XCTAssertFalse(handler.handleUniversalLinkDeepLink(URL(string: "https://example.com/spm")!))
    }

    func testHandleUniversalLinkDeepLink_givenMatchingLink_thenPostsDeepLinkRoute() {
        let storage = StorageManagerStub()
        storage.userEmailId = "test@example.com"
        let notificationCenter = NotificationCenter()
        let notificationExpectation = expectation(description: "Dashboard deep-link route posted")
        let observer = notificationCenter.addObserver(
            forName: .showDeepLinkScreenOnDashboard,
            object: nil,
            queue: .main
        ) { notification in
            XCTAssertEqual(notification.userInfo?["link"] as? String, "/spm")
            notificationExpectation.fulfill()
        }
        defer { notificationCenter.removeObserver(observer) }
        let handler = AppDeepLinksHandlerUtil(storage: storage, notificationCenter: notificationCenter)

        XCTAssertTrue(handler.handleUniversalLinkDeepLink(URL(string: "https://ciosample.page.link/spm")!))
        wait(for: [notificationExpectation], timeout: 1)
    }

    func testHandleCustomerIODestination_givenUniversalLink_thenPostsDeepLinkRoute() {
        let storage = StorageManagerStub()
        storage.userEmailId = "test@example.com"
        let notificationCenter = NotificationCenter()
        let notificationExpectation = expectation(description: "Dashboard deep-link route posted")
        let observer = notificationCenter.addObserver(
            forName: .showDeepLinkScreenOnDashboard,
            object: nil,
            queue: .main
        ) { notification in
            XCTAssertEqual(notification.userInfo?["link"] as? String, "/spm")
            notificationExpectation.fulfill()
        }
        defer { notificationCenter.removeObserver(observer) }
        let handler = AppDeepLinksHandlerUtil(storage: storage, notificationCenter: notificationCenter)

        XCTAssertTrue(handler.handleCustomerIODestination(URL(string: "https://ciosample.page.link/spm")!))
        wait(for: [notificationExpectation], timeout: 1)
    }

    func testHandleCustomerIODestination_givenAppScheme_thenPostsSettingsRoute() {
        let storage = StorageManagerStub()
        storage.userEmailId = "test@example.com"
        let notificationCenter = NotificationCenter()
        let notificationExpectation = expectation(description: "Dashboard settings route posted")
        let observer = notificationCenter.addObserver(
            forName: .showSettingsScreenOnDashboard,
            object: nil,
            queue: .main
        ) { notification in
            XCTAssertEqual(notification.userInfo?["site_id"] as? String, "test")
            notificationExpectation.fulfill()
        }
        defer { notificationCenter.removeObserver(observer) }
        let handler = AppDeepLinksHandlerUtil(storage: storage, notificationCenter: notificationCenter)

        XCTAssertTrue(handler.handleCustomerIODestination(URL(string: "apn-uikit://settings?site_id=test")!))
        wait(for: [notificationExpectation], timeout: 1)
    }

    func testHandleCustomerIODestination_givenForeignScheme_thenReturnsFalse() {
        let handler = AppDeepLinksHandlerUtil(
            storage: StorageManagerStub(),
            notificationCenter: NotificationCenter()
        )

        XCTAssertFalse(handler.handleCustomerIODestination(URL(string: "mailto:support@example.com")!))
    }

    func testHandleCustomerIODestination_givenNonMatchingUniversalLink_thenReturnsFalse() {
        let handler = AppDeepLinksHandlerUtil(
            storage: StorageManagerStub(),
            notificationCenter: NotificationCenter()
        )

        XCTAssertFalse(handler.handleCustomerIODestination(URL(string: "https://example.com/spm")!))
    }

    func testHandleCustomerIODestination_givenUppercaseHTTPSLink_thenReturnsTrue() {
        let handler = AppDeepLinksHandlerUtil(
            storage: StorageManagerStub(),
            notificationCenter: NotificationCenter()
        )

        XCTAssertTrue(handler.handleCustomerIODestination(URL(string: "HTTPS://CIOSAMPLE.PAGE.LINK/spm")!))
    }
}

private final class StorageManagerStub: StorageManager {
    var settings: Settings?
    var userEmailId: String?
    var didSetDefaults: Bool?
}
