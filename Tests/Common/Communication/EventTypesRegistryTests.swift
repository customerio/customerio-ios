@testable import CioInternalCommon
import SharedTests
import XCTest

class EventTypesRegistryTests: UnitTest {
    // MARK: - getEventType(for:) - Known event keys

    func test_getEventType_whenKeyIsProfileIdentifiedEvent_expectReturnsProfileIdentifiedEventType() throws {
        let eventType = try EventTypesRegistry.getEventType(for: ProfileIdentifiedEvent.key)
        XCTAssertEqual(eventType.key, ProfileIdentifiedEvent.key)
    }

    func test_getEventType_whenKeyIsAnonymousProfileIdentifiedEvent_expectReturnsAnonymousProfileIdentifiedEventType() throws {
        let eventType = try EventTypesRegistry.getEventType(for: AnonymousProfileIdentifiedEvent.key)
        XCTAssertEqual(eventType.key, AnonymousProfileIdentifiedEvent.key)
    }

    func test_getEventType_whenKeyIsScreenViewedEvent_expectReturnsScreenViewedEventType() throws {
        let eventType = try EventTypesRegistry.getEventType(for: ScreenViewedEvent.key)
        XCTAssertEqual(eventType.key, ScreenViewedEvent.key)
    }

    func test_getEventType_whenKeyIsResetEvent_expectReturnsResetEventType() throws {
        let eventType = try EventTypesRegistry.getEventType(for: ResetEvent.key)
        XCTAssertEqual(eventType.key, ResetEvent.key)
    }

    func test_getEventType_whenKeyIsTrackMetricEvent_expectReturnsTrackMetricEventType() throws {
        let eventType = try EventTypesRegistry.getEventType(for: TrackMetricEvent.key)
        XCTAssertEqual(eventType.key, TrackMetricEvent.key)
    }

    func test_getEventType_whenKeyIsTrackInAppMetricEvent_expectReturnsTrackInAppMetricEventType() throws {
        let eventType = try EventTypesRegistry.getEventType(for: TrackInAppMetricEvent.key)
        XCTAssertEqual(eventType.key, TrackInAppMetricEvent.key)
    }

    func test_getEventType_whenKeyIsRegisterDeviceTokenEvent_expectReturnsRegisterDeviceTokenEventType() throws {
        let eventType = try EventTypesRegistry.getEventType(for: RegisterDeviceTokenEvent.key)
        XCTAssertEqual(eventType.key, RegisterDeviceTokenEvent.key)
    }

    func test_getEventType_whenKeyIsDeleteDeviceTokenEvent_expectReturnsDeleteDeviceTokenEventType() throws {
        let eventType = try EventTypesRegistry.getEventType(for: DeleteDeviceTokenEvent.key)
        XCTAssertEqual(eventType.key, DeleteDeviceTokenEvent.key)
    }

    func test_getEventType_whenKeyIsNewSubscriptionEvent_expectReturnsNewSubscriptionEventType() throws {
        let eventType = try EventTypesRegistry.getEventType(for: NewSubscriptionEvent.key)
        XCTAssertEqual(eventType.key, NewSubscriptionEvent.key)
    }

    // MARK: - getEventType(for:) - Unknown key

    func test_getEventType_whenKeyIsUnknown_expectThrowsInvalidEventType() {
        XCTAssertThrowsError(try EventTypesRegistry.getEventType(for: "UnknownEventKey")) { error in
            guard case EventBusError.invalidEventType = error else {
                XCTFail("Expected EventBusError.invalidEventType, got \(error)")
                return
            }
        }
    }

    func test_getEventType_whenKeyIsEmpty_expectThrowsInvalidEventType() {
        XCTAssertThrowsError(try EventTypesRegistry.getEventType(for: "")) { error in
            guard case EventBusError.invalidEventType = error else {
                XCTFail("Expected EventBusError.invalidEventType, got \(error)")
                return
            }
        }
    }
}
