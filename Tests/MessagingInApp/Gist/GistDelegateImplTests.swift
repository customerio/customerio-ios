import XCTest
@testable import CioInternalCommon
@testable import CioMessagingInApp
import SharedTests

class GistDelegateImplTests: UnitTest {
    
    var gistDelegate: GistDelegateImpl!
    var mockLogger: LoggerMock!
    var mockEventBusHandler: EventBusHandlerMock!
    var mockEventListener: InAppEventListenerMock!
    var mockThreadUtil: ThreadUtilStub!
    
    override func setUp() {
        super.setUp()
        
        mockLogger = LoggerMock()
        mockEventBusHandler = EventBusHandlerMock()
        mockEventListener = InAppEventListenerMock()
        mockThreadUtil = ThreadUtilStub()
        
        // Override the ThreadUtil in the DIGraphShared
        let originalThreadUtil = diGraphShared.threadUtil
        diGraphShared.override(value: mockThreadUtil, forType: ThreadUtil.self)
        
        gistDelegate = GistDelegateImpl(logger: mockLogger, eventBusHandler: mockEventBusHandler)
        gistDelegate.setEventListener(mockEventListener)
        
        // Reset the original ThreadUtil after creating the gistDelegate
        diGraphShared.override(value: originalThreadUtil, forType: ThreadUtil.self)
    }
    
    override func tearDown() {
        mockLogger = nil
        mockEventBusHandler = nil
        mockEventListener = nil
        mockThreadUtil = nil
        gistDelegate = nil
        
        super.tearDown()
    }
    
    func testSetEventListener() {
        let newMockEventListener = InAppEventListenerMock()
        
        gistDelegate.setEventListener(newMockEventListener)
        
        // Create a test message to verify the event listener is properly set
        let message = Message(messageId: "test-message-id")
        gistDelegate.messageShown(message: message)
        
        XCTAssertFalse(mockEventListener.messageShownCalled, "Old event listener should not be called")
        XCTAssertTrue(newMockEventListener.messageShownCalled, "New event listener should be called")
    }
    
    func testMessageShown() {
        let message = Message(messageId: "test-message-id", campaignId: "test-delivery-id")
        
        gistDelegate.messageShown(message: message)
        
        XCTAssertTrue(mockEventBusHandler.postEventCalled, "EventBusHandler should post an event")
        XCTAssertTrue(mockThreadUtil.runMainCalled, "ThreadUtil.runMain should be called to dismiss keyboard")
        XCTAssertTrue(mockEventListener.messageShownCalled, "EventListener's messageShown should be called")
        
        // Verify event bus event details
        if let postedEvent = mockEventBusHandler.postEventArguments as? TrackInAppMetricEvent {
            XCTAssertEqual(postedEvent.deliveryID, "test-delivery-id", "DeliveryID should match campaign ID")
            XCTAssertEqual(postedEvent.event, InAppMetric.opened.rawValue, "Event should be 'opened'")
        } else {
            XCTFail("Event posted should be TrackInAppMetricEvent")
        }
        
        // Verify event listener details
        XCTAssertEqual(mockEventListener.messageShownReceivedArguments?.messageId, "test-message-id", "Message ID should match")
    }
    
    func testMessageDismissed() {
        let message = Message(messageId: "test-message-id")
        
        gistDelegate.messageDismissed(message: message)
        
        XCTAssertTrue(mockEventListener.messageDismissedCalled, "EventListener's messageDismissed should be called")
        XCTAssertEqual(mockEventListener.messageDismissedReceivedArguments?.messageId, "test-message-id", "Message ID should match")
    }
    
    func testMessageError() {
        let message = Message(messageId: "test-message-id")
        
        gistDelegate.messageError(message: message)
        
        XCTAssertTrue(mockEventListener.errorWithMessageCalled, "EventListener's errorWithMessage should be called")
        XCTAssertEqual(mockEventListener.errorWithMessageReceivedArguments?.messageId, "test-message-id", "Message ID should match")
    }
    
    func testActionWithNormalAction() {
        let message = Message(messageId: "test-message-id", campaignId: "test-delivery-id")
        let action = "https://customerio.com"
        let name = "Visit Website"
        
        gistDelegate.action(message: message, currentRoute: "/test", action: action, name: name)
        
        XCTAssertTrue(mockEventBusHandler.postEventCalled, "EventBusHandler should post an event for non-close actions")
        XCTAssertTrue(mockEventListener.messageActionTakenCalled, "EventListener's messageActionTaken should be called")
        
        // Verify event bus event details
        if let postedEvent = mockEventBusHandler.postEventArguments as? TrackInAppMetricEvent {
            XCTAssertEqual(postedEvent.deliveryID, "test-delivery-id", "DeliveryID should match campaign ID")
            XCTAssertEqual(postedEvent.event, InAppMetric.clicked.rawValue, "Event should be 'clicked'")
            
            if let params = postedEvent.params as? [String: String] {
                XCTAssertEqual(params["actionName"], "Visit Website", "Action name should match")
                XCTAssertEqual(params["actionValue"], "https://customerio.com", "Action value should match")
            } else {
                XCTFail("Event params should be a dictionary of [String: String]")
            }
        } else {
            XCTFail("Event posted should be TrackInAppMetricEvent")
        }
        
        // Verify event listener details
        XCTAssertEqual(mockEventListener.messageActionTakenReceivedArguments?.message.messageId, "test-message-id", "Message ID should match")
        XCTAssertEqual(mockEventListener.messageActionTakenReceivedArguments?.actionValue, "https://customerio.com", "Action value should match")
        XCTAssertEqual(mockEventListener.messageActionTakenReceivedArguments?.actionName, "Visit Website", "Action name should match")
    }
    
    func testActionWithCloseAction() {
        let message = Message(messageId: "test-message-id", campaignId: "test-delivery-id")
        let action = "gist://close"
        let name = "Close"
        
        gistDelegate.action(message: message, currentRoute: "/test", action: action, name: name)
        
        XCTAssertFalse(mockEventBusHandler.postEventCalled, "EventBusHandler should not post an event for close actions")
        XCTAssertTrue(mockEventListener.messageActionTakenCalled, "EventListener's messageActionTaken should be called")
        
        // Verify event listener details
        XCTAssertEqual(mockEventListener.messageActionTakenReceivedArguments?.message.messageId, "test-message-id", "Message ID should match")
        XCTAssertEqual(mockEventListener.messageActionTakenReceivedArguments?.actionValue, "gist://close", "Action value should match")
        XCTAssertEqual(mockEventListener.messageActionTakenReceivedArguments?.actionName, "Close", "Action name should match")
    }
    
    
    func testEmbedMessage() {
        let message = Message(messageId: "test-message-id")
        let elementId = "test-element-id"
        
        // Reset the mocks to ensure we start clean
        mockEventBusHandler.resetMock()
        mockEventListener.resetMock()
        
        gistDelegate.embedMessage(message: message, elementId: elementId)
        
        // Since this is a no-op implementation, verify no events are posted
        // and that the event listener wasn't called
        XCTAssertFalse(mockEventBusHandler.postEventCalled, "No events should be posted")
        XCTAssertFalse(mockEventListener.messageShownCalled, "No event listener methods should be called")
        XCTAssertFalse(mockEventListener.messageDismissedCalled, "No event listener methods should be called")
        XCTAssertFalse(mockEventListener.errorWithMessageCalled, "No event listener methods should be called")
        XCTAssertFalse(mockEventListener.messageActionTakenCalled, "No event listener methods should be called")
    }
}
