@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@_spi(Internal) @testable import CioMessagingPush
import Foundation
import SharedTests
import XCTest

class MessagingPushDeviceTokenTest: UnitTest {
    private let eventBusHandlerMock = EventBusHandlerMock()
    private let globalDataStoreMock = GlobalDataStoreMock()

    override func setUpDependencies() {
        super.setUpDependencies()

        mockCollection.add(mocks: [eventBusHandlerMock, globalDataStoreMock])

        diGraphShared.override(value: eventBusHandlerMock, forType: EventBusHandler.self)
        diGraphShared.override(value: globalDataStoreMock, forType: GlobalDataStore.self)
    }

    private var postedRegisterEvents: [RegisterDeviceTokenEvent] {
        eventBusHandlerMock.postEventReceivedInvocations.compactMap { $0 as? RegisterDeviceTokenEvent }
    }

    func test_registerDeviceToken_givenType_expectEventWithType() {
        MessagingPush.shared.registerDeviceToken("fid-value", tokenType: .fid)

        XCTAssertEqual(postedRegisterEvents.count, 1)
        XCTAssertEqual(postedRegisterEvents.first?.token, "fid-value")
        XCTAssertEqual(postedRegisterEvents.first?.tokenType, .fid)
    }

    func test_registerDeviceToken_givenNoType_expectEventWithoutType() {
        MessagingPush.shared.registerDeviceToken("customer-token")

        XCTAssertEqual(postedRegisterEvents.count, 1)
        XCTAssertNil(postedRegisterEvents.first?.tokenType)
    }

    func test_registerDeviceToken_givenStoredTokenAndType_expectSkipped() {
        globalDataStoreMock.underlyingPushDeviceToken = "fcm-token"
        globalDataStoreMock.underlyingPushDeviceTokenType = .token

        MessagingPush.shared.registerDeviceToken("fcm-token", tokenType: .token)
        MessagingPush.shared.registerDeviceToken("fcm-token")

        XCTAssertTrue(postedRegisterEvents.isEmpty)
    }

    func test_registerDeviceToken_givenStoredTokenWithoutType_expectRegisteredWithType() {
        // e.g. a token stored by an SDK version that didn't save types
        globalDataStoreMock.underlyingPushDeviceToken = "fcm-token"

        MessagingPush.shared.registerDeviceToken("fcm-token", tokenType: .token)

        XCTAssertEqual(postedRegisterEvents.count, 1)
        XCTAssertEqual(postedRegisterEvents.first?.tokenType, .token)
    }

    func test_registerDeviceToken_givenModuleNotInitialized_expectTokenAndTypeStored() {
        MessagingPush.shared._implementation = nil

        MessagingPush.shared.registerDeviceToken("fid-value", tokenType: .fid)

        XCTAssertTrue(postedRegisterEvents.isEmpty)
        XCTAssertEqual(globalDataStoreMock.underlyingPushDeviceToken, "fid-value")
        XCTAssertEqual(globalDataStoreMock.underlyingPushDeviceTokenType, .fid)
    }
}
