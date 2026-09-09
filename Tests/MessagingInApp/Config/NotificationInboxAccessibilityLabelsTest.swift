@testable import CioMessagingInApp
import SharedTests
import XCTest

class NotificationInboxAccessibilityLabelsTest: UnitTest {
    func test_init_givenNoArguments_expectAllLabelsNil() {
        let labels = NotificationInboxAccessibilityLabels()

        XCTAssertNil(labels.bell)
        XCTAssertNil(labels.bellWithUnreadCount)
        XCTAssertNil(labels.loadingIndicator)
        XCTAssertNil(labels.emptyState)
    }

    func test_unreadCountTemplate_givenPlaceholder_expectCountSubstituted() {
        let label = NotificationInboxAccessibilityLabels.unreadCountTemplate("{count} olästa aviseringar")

        XCTAssertEqual(label(3), "3 olästa aviseringar")
        XCTAssertEqual(label(12), "12 olästa aviseringar")
    }

    func test_unreadCountTemplate_givenMultiplePlaceholders_expectAllSubstituted() {
        let label = NotificationInboxAccessibilityLabels.unreadCountTemplate("{count} / {count}")

        XCTAssertEqual(label(7), "7 / 7")
    }

    func test_unreadCountTemplate_givenNoPlaceholder_expectTemplateVerbatim() {
        let label = NotificationInboxAccessibilityLabels.unreadCountTemplate("Unread notifications")

        XCTAssertEqual(label(5), "Unread notifications")
    }
}
