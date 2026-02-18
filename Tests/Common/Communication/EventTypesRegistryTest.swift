@testable import CioInternalCommon
import SharedTests
import XCTest

class EventTypesRegistryTest: UnitTest {
    // MARK: - getEventType

    func test_getEventType_givenProfileIdentifiedEventKey_expectReturnsCorrectType() throws {
        let result = try EventTypesRegistry.getEventType(for: ProfileIdentifiedEvent.key)

        XCTAssertTrue(result == ProfileIdentifiedEvent.self)
    }

    func test_getEventType_givenAnonymousProfileIdentifiedEventKey_expectReturnsCorrectType() throws {
        let result = try EventTypesRegistry.getEventType(for: AnonymousProfileIdentifiedEvent.key)

        XCTAssertTrue(result == AnonymousProfileIdentifiedEvent.self)
    }

    func test_getEventType_givenScreenViewedEventKey_expectReturnsCorrectType() throws {
        let result = try EventTypesRegistry.getEventType(for: ScreenViewedEvent.key)

        XCTAssertTrue(result == ScreenViewedEvent.self)
    }

    func test_getEventType_givenResetEventKey_expectReturnsCorrectType() throws {
        let result = try EventTypesRegistry.getEventType(for: ResetEvent.key)

        XCTAssertTrue(result == ResetEvent.self)
    }

    func test_getEventType_givenTrackMetricEventKey_expectReturnsCorrectType() throws {
        let result = try EventTypesRegistry.getEventType(for: TrackMetricEvent.key)

        XCTAssertTrue(result == TrackMetricEvent.self)
    }

    func test_getEventType_givenTrackInAppMetricEventKey_expectReturnsCorrectType() throws {
        let result = try EventTypesRegistry.getEventType(for: TrackInAppMetricEvent.key)

        XCTAssertTrue(result == TrackInAppMetricEvent.self)
    }

    func test_getEventType_givenRegisterDeviceTokenEventKey_expectReturnsCorrectType() throws {
        let result = try EventTypesRegistry.getEventType(for: RegisterDeviceTokenEvent.key)

        XCTAssertTrue(result == RegisterDeviceTokenEvent.self)
    }

    func test_getEventType_givenDeleteDeviceTokenEventKey_expectReturnsCorrectType() throws {
        let result = try EventTypesRegistry.getEventType(for: DeleteDeviceTokenEvent.key)

        XCTAssertTrue(result == DeleteDeviceTokenEvent.self)
    }

    func test_getEventType_givenNewSubscriptionEventKey_expectReturnsCorrectType() throws {
        let result = try EventTypesRegistry.getEventType(for: NewSubscriptionEvent.key)

        XCTAssertTrue(result == NewSubscriptionEvent.self)
    }

    func test_getEventType_givenTrackLocationEventKey_expectReturnsCorrectType() throws {
        let result = try EventTypesRegistry.getEventType(for: TrackLocationEvent.key)

        XCTAssertTrue(result == TrackLocationEvent.self)
    }

    func test_getEventType_givenLocationTrackedEventKey_expectReturnsCorrectType() throws {
        let result = try EventTypesRegistry.getEventType(for: LocationTrackedEvent.key)

        XCTAssertTrue(result == LocationTrackedEvent.self)
    }

    func test_getEventType_givenInvalidKey_expectThrowsError() {
        XCTAssertThrowsError(try EventTypesRegistry.getEventType(for: "InvalidEventKey")) { error in
            XCTAssertEqual(error as? EventBusError, EventBusError.invalidEventType)
        }
    }

    // MARK: - Consistency between allEventTypes and getEventType

    func test_getEventType_givenAllEventTypes_expectAllCanBeRetrievedByKey() throws {
        for eventType in EventTypesRegistry.allEventTypes() {
            let retrievedType = try EventTypesRegistry.getEventType(for: eventType.key)
            XCTAssertTrue(retrievedType == eventType, "getEventType should return the same type for key: \(eventType.key)")
        }
    }

    func test_allEventTypes_expectContainsAllExpectedTypes() {
        let allTypes = EventTypesRegistry.allEventTypes()

        XCTAssertTrue(allTypes.contains { $0 == ProfileIdentifiedEvent.self })
        XCTAssertTrue(allTypes.contains { $0 == AnonymousProfileIdentifiedEvent.self })
        XCTAssertTrue(allTypes.contains { $0 == ScreenViewedEvent.self })
        XCTAssertTrue(allTypes.contains { $0 == ResetEvent.self })
        XCTAssertTrue(allTypes.contains { $0 == TrackMetricEvent.self })
        XCTAssertTrue(allTypes.contains { $0 == TrackInAppMetricEvent.self })
        XCTAssertTrue(allTypes.contains { $0 == RegisterDeviceTokenEvent.self })
        XCTAssertTrue(allTypes.contains { $0 == DeleteDeviceTokenEvent.self })
        XCTAssertTrue(allTypes.contains { $0 == NewSubscriptionEvent.self })
        XCTAssertTrue(allTypes.contains { $0 == TrackLocationEvent.self })
        XCTAssertTrue(allTypes.contains { $0 == LocationTrackedEvent.self })
    }
}
