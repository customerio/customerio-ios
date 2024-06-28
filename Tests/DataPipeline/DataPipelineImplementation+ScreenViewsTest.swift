@testable import CioDataPipelines
import CioInternalCommon
import Foundation
import SharedTests
import SwiftUI
import UIKit
import XCTest

class DataPipelineScreenViewsTest: IntegrationTest {
    private var autoTrackingScreenViews: AutoTrackingScreenViews!
    private var outputReader: OutputReaderPlugin!

    override func setUp() {
        super.setUp()

        // setting up required plugins
        outputReader = (CustomerIO.shared.add(plugin: OutputReaderPlugin()) as! OutputReaderPlugin) // swiftlint:disable:this force_cast
        autoTrackingScreenViews = getTrackingScreenViewsPlugin()
    }

    private func getTrackingScreenViewsPlugin() -> AutoTrackingScreenViews {
        (CustomerIO.shared.add(plugin: AutoTrackingScreenViews()) as! AutoTrackingScreenViews) // swiftlint:disable:this force_cast
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

    func test_performScreenTracking_givenViewSameScreenMultipleTimes_expectNoTrackingDuplicateEvents() {
        class ViewInsideOfHostApp: UIViewController {}
        class AnotherViewInsideOfHostApp: UIViewController {}

        // The first time that the screen is tracked, an event should be added
        autoTrackingScreenViews.performScreenTracking(onViewController: ViewInsideOfHostApp())
        assertEventTracked(numberOfEventsAdded: 1)

        // If the screen is tracked again, ignore the event.
        autoTrackingScreenViews.performScreenTracking(onViewController: ViewInsideOfHostApp())
        assertEventTracked(numberOfEventsAdded: 1)

        // Check that an event is added, if the next screen is not equal to the last screen tracked.
        autoTrackingScreenViews.performScreenTracking(onViewController: AnotherViewInsideOfHostApp())
        assertEventTracked(numberOfEventsAdded: 2)
    }

    func test_performScreenTracking_givenChangeScreen_expectTrackNonDuplicateScreens() {
        class ViewInsideOfHostApp: UIViewController {}
        class AnotherViewInsideOfHostApp: UIViewController {}

        // The first time that the screen is tracked, an event should be added
        autoTrackingScreenViews.performScreenTracking(onViewController: ViewInsideOfHostApp())
        assertEventTracked(numberOfEventsAdded: 1)

        // Change to a different screen, expect to track it.
        autoTrackingScreenViews.performScreenTracking(onViewController: AnotherViewInsideOfHostApp())
        assertEventTracked(numberOfEventsAdded: 2)

        // Re-visit the first screen again, expect to track it.
        autoTrackingScreenViews.performScreenTracking(onViewController: ViewInsideOfHostApp())
        assertEventTracked(numberOfEventsAdded: 3)
    }

    func test_performScreenTracking_givenMultiplePluginInstances_expectNoTrackingDuplicateEvents() {
        class ViewInsideOfHostApp: UIViewController {}

        let plugin1 = getTrackingScreenViewsPlugin()
        let plugin2 = getTrackingScreenViewsPlugin()

        plugin1.performScreenTracking(onViewController: ViewInsideOfHostApp())
        assertEventTracked(numberOfEventsAdded: 1)

        plugin2.performScreenTracking(onViewController: ViewInsideOfHostApp())
        assertEventTracked(numberOfEventsAdded: 1)
    }

    func test_performScreenTracking_givenScreenInheritsDoNotTrackScreenViewEvent_expectNoTracking() {
        class DoNotTrackScreen: UIViewController, DoNotTrackScreenViewEvent {}

        autoTrackingScreenViews.performScreenTracking(onViewController: DoNotTrackScreen())

        assertNoEventTracked()
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

extension DataPipelineScreenViewsTest {
    private func assertNoEventTracked() {
        guard let outputReader = outputReader else {
            XCTFail("Expected non-nil outputReader")
            return
        }

        let screenviewEvents = outputReader.screenEvents
        XCTAssertEqual(screenviewEvents.count, 0)
    }

    private func assertEventTracked(numberOfEventsAdded: Int = 1) {
        guard let outputReader = outputReader else {
            XCTFail("Expected non-nil outputReader")
            return
        }

        let screenviewEvents = outputReader.screenEvents
        XCTAssertEqual(screenviewEvents.count, numberOfEventsAdded)
    }
}
