import SharedTests
import UIKit
import XCTest

@testable import CioInternalCommon
@testable import CioMessagingInApp

class GistModalViewControllerKeyboardTests: UnitTest {
    private let viewHeight: CGFloat = 874
    private let topInset: CGFloat = 62

    private func layout(
        _ position: MessagePosition,
        contentHeight: CGFloat,
        keyboardOverlap: CGFloat
    ) -> (height: CGFloat, verticalOffset: CGFloat) {
        GistModalViewController.layout(
            position: position,
            viewHeight: viewHeight,
            contentHeight: contentHeight,
            keyboardOverlap: keyboardOverlap,
            topInset: topInset
        )
    }

    // MARK: - layout

    func test_layout_givenNoKeyboard_expectContentHeightAndNoOffset() {
        for position in [MessagePosition.top, .center, .bottom] {
            let result = layout(position, contentHeight: 446, keyboardOverlap: 0)

            XCTAssertEqual(result.height, 446, "\(position)")
            XCTAssertEqual(result.verticalOffset, 0, "\(position)")
        }
    }

    func test_layout_givenNoKeyboardAndTallContent_expectHeightCappedToView() {
        let result = layout(.center, contentHeight: 1000, keyboardOverlap: 0)

        XCTAssertEqual(result.height, 874)
        XCTAssertEqual(result.verticalOffset, 0)
    }

    func test_layout_givenCenterAndKeyboard_expectCenteredAboveKeyboard() {
        let result = layout(.center, contentHeight: 446, keyboardOverlap: 336)

        XCTAssertEqual(result.height, 446)
        // Centered between the safe area top (62) and the keyboard top (538).
        XCTAssertEqual(result.verticalOffset, -137)
    }

    func test_layout_givenCenterAndOverlapSmallerThanTopInset_expectNotMovedDown() {
        let result = layout(.center, contentHeight: 446, keyboardOverlap: 40)

        XCTAssertEqual(result.height, 446)
        XCTAssertEqual(result.verticalOffset, 0)
    }

    func test_layout_givenCenterAndContentTallerThanSpace_expectHeightCapped() {
        let result = layout(.center, contentHeight: 600, keyboardOverlap: 336)

        XCTAssertEqual(result.height, 476)
        XCTAssertEqual(result.verticalOffset, -137)
    }

    func test_layout_givenBottomAndKeyboard_expectBottomAtKeyboardTop() {
        let result = layout(.bottom, contentHeight: 446, keyboardOverlap: 336)

        XCTAssertEqual(result.height, 446)
        XCTAssertEqual(result.verticalOffset, -336)
    }

    func test_layout_givenBottomAndContentTallerThanSpace_expectHeightCapped() {
        let result = layout(.bottom, contentHeight: 600, keyboardOverlap: 336)

        XCTAssertEqual(result.height, 476)
        XCTAssertEqual(result.verticalOffset, -336)
    }

    func test_layout_givenTopAndKeyboard_expectStaysPinnedAndOnlyShrinks() {
        XCTAssertEqual(layout(.top, contentHeight: 200, keyboardOverlap: 336).height, 200)
        XCTAssertEqual(layout(.top, contentHeight: 600, keyboardOverlap: 336).height, 538)
        XCTAssertEqual(layout(.top, contentHeight: 600, keyboardOverlap: 336).verticalOffset, 0)
    }

    func test_layout_givenKeyboardTallerThanView_expectZeroHeight() {
        XCTAssertEqual(layout(.bottom, contentHeight: 446, keyboardOverlap: 1000).height, 0)
        XCTAssertEqual(layout(.top, contentHeight: 446, keyboardOverlap: 1000).height, 0)
    }

    // MARK: - keyboard notifications

    func test_keyboardWillChangeFrame_expectOverlapTracksKeyboardAndResets() {
        let gistView = GistView(message: Message(messageId: "test-message"), engineView: UIView())
        let viewController = GistModalViewController()
        viewController.gistView = gistView
        viewController.setup(position: .bottom)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        window.rootViewController = viewController
        window.isHidden = false
        viewController.view.layoutIfNeeded()

        // The window sits at the screen origin, so window coordinates are screen coordinates.
        let viewBottom = viewController.view.convert(viewController.view.bounds, to: nil).maxY

        postKeyboardFrame(CGRect(x: 0, y: viewBottom - 300, width: 400, height: 300))
        XCTAssertEqual(viewController.keyboardOverlap, 300)
        XCTAssertEqual(viewController.verticalConstraint.constant, -300)

        postKeyboardFrame(CGRect(x: 0, y: viewBottom, width: 400, height: 300))
        XCTAssertEqual(viewController.keyboardOverlap, 0)
        XCTAssertEqual(viewController.verticalConstraint.constant, 0)

        window.isHidden = true
    }

    private func postKeyboardFrame(_ frame: CGRect) {
        NotificationCenter.default.post(
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey: frame,
                UIResponder.keyboardAnimationDurationUserInfoKey: 0.0
            ]
        )
    }
}
