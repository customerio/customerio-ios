@testable import CioTracking
import Foundation
import SharedTests
import SwiftUI
import UIKit
import XCTest

class UIKitExtensionsTest: UnitTest {
    // MARK: bundleIdOfView

    func test_bundleIdOfView_givenSwiftUIView_expectAppleBundleId() {
        XCTAssertEqual(SwiftUI.UIHostingController(rootView: Text("")).bundleIdOfView, "com.apple.SwiftUI")
    }

    func test_bundleIdOfView_givenUIKitView_expectAppleBundleId() {
        XCTAssertEqual(UIAlertController().bundleIdOfView, "com.apple.UIKitCore")
    }

    func test_bundleIdOfView_givenViewFromHostApp_expectHostAppBundleId() {
        class MyViewController: UIViewController {}

        XCTAssertEqual(MyViewController().bundleIdOfView, "CommonTests") // CommonTests is value because the ViewController class above exists in the Tests target named CommonTests.
    }
}
