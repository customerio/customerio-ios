import XCTest
@testable import CioInternalCommon
@testable import CioMessagingInApp
import SharedTests

class GistViewLifecycleDelegateTests: UnitTest {
    
    class MockGistViewLifecycleDelegate: GistViewLifecycleDelegate {
        var removeFromSuperviewCalled = false
        var lastGistView: GistView?
        
        public func gistViewWillRemoveFromSuperview(_ gistView: GistView) {
            removeFromSuperviewCalled = true
            lastGistView = gistView
        }
    }
    
    var gistView: GistView!
    var mockLifecycleDelegate: MockGistViewLifecycleDelegate!
    var mockEngineView: UIView!
    var mockGistProvider: GistProviderMock!
    var originalGistProvider: GistProvider!
    
    override func setUp() {
        super.setUp()
        
        mockLifecycleDelegate = MockGistViewLifecycleDelegate()
        mockEngineView = UIView()
        mockGistProvider = GistProviderMock()
        
        originalGistProvider = diGraphShared.gistProvider
        diGraphShared.override(value: mockGistProvider, forType: GistProvider.self)
        
        let message = Message(messageId: "test-message")
        gistView = GistView(message: message, engineView: mockEngineView)
        gistView.lifecycleDelegate = mockLifecycleDelegate
    }
    
    override func tearDown() {
        diGraphShared.override(value: originalGistProvider, forType: GistProvider.self)
        
        mockLifecycleDelegate = nil
        mockEngineView = nil
        mockGistProvider = nil
        gistView = nil
        
        super.tearDown()
    }
    
    func testLifecycleDelegateCalledWhenRemovingFromSuperview() {
        gistView.removeFromSuperview()
        
        XCTAssertTrue(mockLifecycleDelegate.removeFromSuperviewCalled, "Lifecycle delegate should be notified when removeFromSuperview is called")
        XCTAssertTrue(mockLifecycleDelegate.lastGistView === gistView, "The correct GistView should be passed to the delegate")
        XCTAssertFalse(mockGistProvider.dismissMessageCalled, "GistView should not directly call dismissMessage after our refactoring")
    }
    
    func testInlineMessageManagerImplementation() {
        let message = Message(messageId: "test-inline-message", elementId: "test-element")
        XCTAssertTrue(message.isEmbedded, "Message should be identified as embedded/inline")
        
        let state = InAppMessageState()
        let inlineManager = InlineMessageManager(state: state, message: message)
        gistView.lifecycleDelegate = inlineManager
        
        gistView.removeFromSuperview()
        
        XCTAssertTrue(mockGistProvider.dismissMessageCalled, 
                     "InlineMessageManager should call dismissMessage when GistView is removed from superview")
    }
    
    func testModalMessageManagerImplementation() {
        // Modal messages don't have an elementId
        let message = Message(messageId: "test-modal-message")
        XCTAssertFalse(message.isEmbedded, "Message should be identified as modal (not embedded/inline)")
        
        let state = InAppMessageState()
        let modalManager = ModalMessageManager(state: state, message: message)
        
        mockGistProvider.resetMock()
        gistView.lifecycleDelegate = modalManager
        
        gistView.removeFromSuperview()
        
        XCTAssertFalse(mockGistProvider.dismissMessageCalled, 
                      "ModalMessageManager should NOT call dismissMessage when GistView is removed from superview")
    }
}
