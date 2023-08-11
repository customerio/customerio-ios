@testable import CioInternalCommon
@testable import CioTracking
import Foundation
import SharedTests
import SwiftUI
import UIKit
import XCTest

class CustomerIOImplementation_ScreenViewsTest: IntegrationTest {
    // MARK: shouldTrackAutomaticScreenviewEvent

    func test_shouldTrackAutomaticScreenviewEvent_givenSdkNotInitialized_expectFalse() {
        uninitializeSDK()

        let viewController = UIViewController()
        XCTAssertFalse(viewController.shouldTrackAutomaticScreenviewEvent())
    }

    func test_shouldTrackAutomaticScreenviewEvent_givenCustomerProvidesFilter_expectSdkDefaultFilterNotUsed() {
        var customerProvidedFilterCalled = false
        setUp(modifySdkConfig: { config in
            config.filterAutoScreenViewEvents = { _ in
                customerProvidedFilterCalled = true

                return true
            }
        })
        let deviceInfoMock = DeviceInfoMock()
        diGraph.override(value: deviceInfoMock, forType: DeviceInfo.self)

        let viewController = UIViewController()
        XCTAssertTrue(viewController.shouldTrackAutomaticScreenviewEvent())

        XCTAssertTrue(customerProvidedFilterCalled)
        XCTAssertFalse(deviceInfoMock.mockCalled) // TODO: this might give false positives in test if the implementation of the default filter ever changes. May be worth mocking the filter itself to see if the filter function called.
    }

    // SwiftUI wraps UIKit views and displays them in your app. Therefore, there is a good chance that automatic screenview tracking for a SwiftUI app will try to track screenview events from Views belonging to the SwiftUI framework. Our SDK, by default, filters those events out.
    func test_shouldTrackAutomaticScreenviewEvent_givenViewFromSwiftUI_expectFalse() {
        let swiftUIView = SwiftUI.UIHostingController(rootView: Text(""))

        XCTAssertFalse(swiftUIView.shouldTrackAutomaticScreenviewEvent())
    }

    func test_shouldTrackAutomaticScreenviewEvent_givenViewFromHostApp_expectTrue() {
        // View that does not belong to a 3rd party framework.
        class ViewInsideOfHostApp: UIViewController {}

        let viewController = ViewInsideOfHostApp()
        deviceInfoStub.customerBundleId = viewController.bundleIdOfView! // set mock that controls the filter function.

        XCTAssertTrue(viewController.shouldTrackAutomaticScreenviewEvent())
    }
}
