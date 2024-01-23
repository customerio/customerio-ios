@testable import CioDataPipelines
@testable import CioInternalCommon
@testable import CioTracking
import Foundation
import SharedTests
import SwiftUI
import UIKit
import XCTest

class DataPipelineImplementationScreenViewsTest: IntegrationTest {
    private var autoTrackingScreenViews: AutoTrackingScreenViews!
    private var outputReader: OutputReaderPlugin!

    override func setUp() {
        super.setUp()

        guard let analytics = CustomerIO.shared.analytics else {
            fatalError("Analytics instance is nil. The SDK has been set up incorrectly.")
        }

        // setting up required plugins
        outputReader = analytics.addPluginOnce(plugin: OutputReaderPlugin())
        autoTrackingScreenViews = analytics.addPluginOnce(plugin: AutoTrackingScreenViews())
        // wait for analytics queue to start emitting events
        analytics.waitUntilStarted()

        // Screenview events are ignored if no profile identified
        CustomerIO.shared.identify(identifier: String.random)
    }

    override func tearDown() {
        CustomerIO.shared.clearIdentify()
        super.tearDown()
    }

    // MARK: performScreenTracking

    func test_performScreenTracking_givenCustomerProvidesFilter_expectSdkDefaultFilterNotUsed() {
        var customerProvidedFilterCalled = false
        autoTrackingScreenViews.filterAutoScreenViewEvents = { _ in
            customerProvidedFilterCalled = true

            return true
        }

        autoTrackingScreenViews.performScreenTracking(onViewController: UIAlertController())

        XCTAssertTrue(customerProvidedFilterCalled)
        assertEventTracked()
    }

    // SwiftUI wraps UIKit views and displays them in your app. Therefore, there is a good chance that automatic screenview tracking for a SwiftUI app will try to track screenview events from Views belonging to the SwiftUI framework or UIKit framework. Our SDK, by default, filters those events out.
    func test_performScreenTracking_givenViewFromSwiftUI_expectFalse() {
        autoTrackingScreenViews.performScreenTracking(onViewController: SwiftUI.UIHostingController(rootView: Text("")))

        assertNoEventTracked()
    }

    // Our SDK believes that UIKit framework views are irrelevant to tracking data for customers. Our SDK, by default, filters those events out.
    func test_performScreenTracking_givenViewFromUIKit_expectFalse() {
        autoTrackingScreenViews.performScreenTracking(onViewController: UIAlertController())

        assertNoEventTracked()
    }

    func test_performScreenTracking_givenViewFromHostApp_expectTrue() {
        class ViewInsideOfHostApp: UIViewController {}

        autoTrackingScreenViews.performScreenTracking(onViewController: ViewInsideOfHostApp())

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

extension DataPipelineImplementationScreenViewsTest {
    private func assertNoEventTracked() {
        XCTAssertTrue(diGraph.queueStorage.filterTrackEvents(.trackEvent).isEmpty)
    }

    private func assertEventTracked(numberOfEventsAdded: Int = 1) {
        let screenviewEvents = outputReader.screenEvents

        XCTAssertEqual(screenviewEvents.count, numberOfEventsAdded)
    }
}
