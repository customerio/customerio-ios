@testable import CioInternalCommon
@testable import CioTracking
import Foundation
import SharedTests
import SwiftUI
import UIKit
import XCTest

class CustomerIOImplementationScreenViewsTest: IntegrationTest {
    override func setUp() {
        super.setUp()

        // Screenview events are ignored if no profile identified
        CustomerIO.shared.identify(identifier: String.random)
    }

    // MARK: performScreenTracking

    func test_performScreenTracking_givenCustomerProvidesFilter_expectSdkDefaultFilterNotUsed() {
        var customerProvidedFilterCalled = false
        setUp(modifySdkConfig: { config in
            config.filterAutoScreenViewEvents = { _ in
                customerProvidedFilterCalled = true

                return true
            }
        })

        CustomerIO.shared.performScreenTracking(onViewController: UIAlertController())

        XCTAssertTrue(customerProvidedFilterCalled)
        assertEventTracked()
    }

    // SwiftUI wraps UIKit views and displays them in your app. Therefore, there is a good chance that automatic screenview tracking for a SwiftUI app will try to track screenview events from Views belonging to the SwiftUI framework or UIKit framework. Our SDK, by default, filters those events out.
    func test_performScreenTracking_givenViewFromSwiftUI_expectFalse() {
        CustomerIO.shared.performScreenTracking(onViewController: SwiftUI.UIHostingController(rootView: Text("")))

        assertNoEventTracked()
    }

    // Our SDK believes that UIKit framework views are irrelevant to tracking data for customers. Our SDK, by default, filters those events out.
    func test_performScreenTracking_givenViewFromUIKit_expectFalse() {
        CustomerIO.shared.performScreenTracking(onViewController: UIAlertController())

        assertNoEventTracked()
    }

    func test_performScreenTracking_givenViewFromHostApp_expectTrue() {
        class ViewInsideOfHostApp: UIViewController {}

        CustomerIO.shared.performScreenTracking(onViewController: ViewInsideOfHostApp())

        assertEventTracked()
    }

    // MARK: getNameForAutomaticScreenViewTracking

    func test_getNameForAutomaticScreenViewTracking_givenViewWithNoTitle_expectNil() {
        class ViewController: UIViewController {}

        let view = ViewController()
        view.title = nil

        XCTAssertNil(view.getNameForAutomaticScreenViewTracking())
    }

    func test_getNameForAutomaticScreenViewTracking_givenViewWithTooBasicName_expectNil() {
        class ViewController: UIViewController {}
        let view = ViewController()

        XCTAssertNil(view.getNameForAutomaticScreenViewTracking())
    }

    func test_getNameForAutomaticScreenViewTracking_givenView_expectCleanupName() {
        class LoginViewController: UIViewController {}

        let view = LoginViewController()

        XCTAssertEqual(view.getNameForAutomaticScreenViewTracking(), "Login")
    }
}

extension CustomerIOImplementationScreenViewsTest {
    private func assertNoEventTracked() {
        XCTAssertTrue(diGraph.queueStorage.filterTrackEvents(.trackEvent).isEmpty)
    }

    private func assertEventTracked(numberOfEventsAdded: Int = 1) {
        let screenviewEvents = diGraph.queueStorage.filterTrackEvents(.trackEvent)

        XCTAssertEqual(screenviewEvents.count, numberOfEventsAdded)
    }
}
