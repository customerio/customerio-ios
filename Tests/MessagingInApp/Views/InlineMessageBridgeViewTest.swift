@testable import CioInternalCommon
@testable import CioMessagingInApp
import SharedTests
import UIKit
import XCTest

class InlineMessageBridgeViewTest: UnitTest {
    private var bridgeView: InlineMessageBridgeView!
    private var mockDelegate: InlineMessageBridgeViewDelegateMock!
    private var parentView: UIView!

    override func setUp() {
        super.setUp()

        diGraphShared.override(value: EventBusHandlerMock(), forType: EventBusHandler.self)

        bridgeView = InlineMessageBridgeView()
        mockDelegate = InlineMessageBridgeViewDelegateMock()
        parentView = UIView()
    }

    override func tearDown() {
        bridgeView = nil
        mockDelegate = nil
        parentView = nil

        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInit_shouldCreateViewWithoutParameters() {
        XCTAssertNotNil(bridgeView)
        XCTAssertNil(bridgeView.elementId)
        XCTAssertNil(bridgeView.delegate)
    }

    // MARK: - Attachment Tests

    func testAttachToParent_shouldSetDelegateAndAddToParent() {
        bridgeView.attachToParent(parent: parentView, delegate: mockDelegate)

        XCTAssertTrue(bridgeView.delegate === mockDelegate)
        XCTAssertEqual(bridgeView.superview, parentView)
        XCTAssertTrue(parentView.subviews.contains(bridgeView))
    }

    func testAttachToParent_shouldSetupConstraints() {
        bridgeView.attachToParent(parent: parentView, delegate: mockDelegate)

        XCTAssertFalse(bridgeView.translatesAutoresizingMaskIntoConstraints)
        XCTAssertEqual(bridgeView.constraints.count + parentView.constraints.count, 4)
    }

    // MARK: - Element ID Tests

    func testSetElementId_shouldTriggerSetup() {
        let elementId = "test-element-id"

        bridgeView.elementId = elementId

        XCTAssertEqual(bridgeView.elementId, elementId)
    }

    func testSetElementId_withExistingView_shouldUpdateElementId() {
        let firstElementId = "first-element-id"
        let secondElementId = "second-element-id"

        bridgeView.elementId = firstElementId
        bridgeView.elementId = secondElementId

        XCTAssertEqual(bridgeView.elementId, secondElementId)
    }

    func testSetElementId_withNilValue_shouldNotCreateView() {
        bridgeView.elementId = nil

        XCTAssertNil(bridgeView.subviews.first { $0 is GistInlineMessageUIView })
    }

    // MARK: - Lifecycle Tests

    func testOnViewAttached_shouldSetupInlineView() {
        bridgeView.elementId = "test-element-id"

        bridgeView.onViewAttached()

        // View setup should be triggered
        XCTAssertNotNil(bridgeView.elementId)
    }

    func testOnViewDetached_shouldTeardownView() {
        bridgeView.elementId = "test-element-id"
        bridgeView.onViewAttached()

        bridgeView.onViewDetached()

        // Should not crash and should handle teardown gracefully
        XCTAssertNotNil(bridgeView)
    }

    func testDeinit_shouldCallOnViewDetached() {
        bridgeView.elementId = "test-element-id"

        // Release the view - this should trigger deinit and call onViewDetached
        bridgeView = nil

        // Should not crash during deinitialization
        XCTAssertTrue(true)
    }
}

// MARK: - GistInlineMessageUIViewDelegate Tests

extension InlineMessageBridgeViewTest {
    func testOnMessageRendered_shouldNotifyDelegate() {
        let width: CGFloat = 300
        let height: CGFloat = 200

        // Set up the bridge view with element ID to create inAppMessageView
        bridgeView.elementId = "test-element-id"
        bridgeView.delegate = mockDelegate
        bridgeView.onMessageRendered(width: width, height: height)

        XCTAssertEqual(mockDelegate.onMessageSizeChangedCallsCount, 1)
        XCTAssertEqual(mockDelegate.onMessageSizeChangedReceivedArguments?.width, width)
        XCTAssertEqual(mockDelegate.onMessageSizeChangedReceivedArguments?.height, height)
        XCTAssertEqual(mockDelegate.onFinishLoadingCallsCount, 1)
    }

    func testOnMessageRendered_withSameDimensions_shouldNotNotifyDelegate() {
        let width: CGFloat = 300
        let height: CGFloat = 200

        // Set up the bridge view with element ID to create inAppMessageView
        bridgeView.elementId = "test-element-id"
        bridgeView.delegate = mockDelegate

        // First call should notify
        bridgeView.onMessageRendered(width: width, height: height)

        // Second call with same dimensions should not notify
        bridgeView.onMessageRendered(width: width, height: height)

        XCTAssertEqual(mockDelegate.onMessageSizeChangedCallsCount, 1)
        XCTAssertEqual(mockDelegate.onFinishLoadingCallsCount, 1)
    }

    func testOnMessageRendered_withDifferentDimensions_shouldNotifyDelegate() {
        // Set up the bridge view with element ID to create inAppMessageView
        bridgeView.elementId = "test-element-id"
        bridgeView.delegate = mockDelegate

        bridgeView.onMessageRendered(width: 300, height: 200)
        bridgeView.onMessageRendered(width: 400, height: 300)

        XCTAssertEqual(mockDelegate.onMessageSizeChangedCallsCount, 2)
        XCTAssertEqual(mockDelegate.onFinishLoadingCallsCount, 2)
    }

    func testOnMessageRendered_withNilInAppMessageView_shouldNotNotifyDelegate() {
        // Don't set element ID, so inAppMessageView remains nil
        bridgeView.delegate = mockDelegate

        bridgeView.onMessageRendered(width: 300, height: 200)

        // Should not notify delegate when inAppMessageView is nil
        XCTAssertEqual(mockDelegate.onMessageSizeChangedCallsCount, 0)
        XCTAssertEqual(mockDelegate.onFinishLoadingCallsCount, 0)
    }

    func testOnNoMessageToDisplay_shouldNotifyDelegateAndClearCache() {
        // Set up the bridge view with element ID to create inAppMessageView
        bridgeView.elementId = "test-element-id"
        bridgeView.delegate = mockDelegate

        // Set some cached dimensions first
        bridgeView.onMessageRendered(width: 300, height: 200)

        bridgeView.onNoMessageToDisplay()

        XCTAssertEqual(mockDelegate.onNoMessageToDisplayCallsCount, 1)
        // Should also call onMessageRendered with 0,0 dimensions
        XCTAssertEqual(mockDelegate.onMessageSizeChangedCallsCount, 2)
        XCTAssertEqual(mockDelegate.onMessageSizeChangedReceivedInvocations.last?.width, 0)
        XCTAssertEqual(mockDelegate.onMessageSizeChangedReceivedInvocations.last?.height, 0)

        // After clearing cache, same dimensions should notify again
        bridgeView.onMessageRendered(width: 300, height: 200)
        XCTAssertEqual(mockDelegate.onMessageSizeChangedCallsCount, 3)
    }

    func testOnInlineButtonAction_shouldNotifyDelegateAndReturnResult() {
        let message = Message()
        let actionValue = "test-action-value"
        let actionName = "test-action-name"

        bridgeView.delegate = mockDelegate
        mockDelegate.onActionClickReturnValue = true

        let result = bridgeView.onInlineButtonAction(
            message: message,
            currentRoute: "test-route",
            action: actionValue,
            name: actionName
        )

        XCTAssertEqual(mockDelegate.onActionClickCallsCount, 1)
        XCTAssertEqual(mockDelegate.onActionClickReceivedArguments?.actionValue, actionValue)
        XCTAssertEqual(mockDelegate.onActionClickReceivedArguments?.actionName, actionName)
        XCTAssertTrue(result)
    }

    func testOnInlineButtonAction_withNilDelegate_shouldReturnFalse() {
        let message = Message()

        bridgeView.delegate = nil

        let result = bridgeView.onInlineButtonAction(
            message: message,
            currentRoute: "test-route",
            action: "action",
            name: "name"
        )

        XCTAssertFalse(result)
    }

    func testWillChangeMessage_shouldNotifyDelegateWithCompletion() {
        let expectation = XCTestExpectation(description: "Completion should be called")

        bridgeView.delegate = mockDelegate
        mockDelegate.onStartLoadingClosure = { onComplete in
            onComplete()
            expectation.fulfill()
        }

        bridgeView.willChangeMessage(newTemplateId: "new-template") {
            // Completion block
        }

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(mockDelegate.onStartLoadingCallsCount, 1)
    }

    func testWillChangeMessage_withNilDelegate_shouldCallCompletion() {
        let expectation = XCTestExpectation(description: "Completion should be called")

        bridgeView.delegate = nil

        bridgeView.willChangeMessage(newTemplateId: "new-template") {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }
}
