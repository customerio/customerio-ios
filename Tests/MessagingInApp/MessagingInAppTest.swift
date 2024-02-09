@testable import CioInternalCommon
@testable import CioMessagingInApp
import Foundation
import SharedTests
import XCTest

class MessagingInAppTest: UnitTest {
    private let implementationMock = MessagingInAppInstanceMock()

    override func initializeSDKComponents() -> MessagingInAppInstance? {
        // Don't initialize the SDK components because we may want to test the initialize function differently in each test.
        nil
    }

    // MARK: initialize functions with Module initialized

    func test_initialize_givenModuleInitialized_expectModuleIsInitialized() {
        MessagingInApp.setUpSharedInstanceForUnitTest(implementation: implementationMock)

        assertModuleInitialized(isInitialized: true, givenEventListener: nil)
    }

    func test_setEventListener_givenModuleInitialized_expectListenerIsSet() {
        let givenListener = InAppEventListenerMock()

        MessagingInApp.setUpSharedInstanceForUnitTest(implementation: implementationMock)
        MessagingInApp.shared.setEventListener(givenListener)

        assertModuleInitialized(isInitialized: true, givenEventListener: givenListener)
    }

    func test_clearEventListener_givenModuleInitialized_expectListenerIsCleared() {
        let givenListener = InAppEventListenerMock()

        MessagingInApp.setUpSharedInstanceForUnitTest(implementation: implementationMock)
        MessagingInApp.shared.setEventListener(givenListener)
        // clear event listener
        MessagingInApp.shared.setEventListener(nil)

        assertModuleInitialized(isInitialized: true, givenEventListener: nil, setEventListenerCallsCount: 2)
    }

    // MARK: initialize functions with Module not initialized

    func test_setEventListener_givenModuleNotInitialized_expectListenerNotSet() {
        let givenListener = InAppEventListenerMock()

        MessagingInApp.shared.setEventListener(givenListener)

        assertModuleInitialized(isInitialized: false, givenEventListener: nil)
    }
}

extension MessagingInAppTest {
    private func assertModuleInitialized(isInitialized: Bool, givenEventListener: InAppEventListener?, setEventListenerCallsCount: Int? = nil, file: StaticString = #file, line: UInt = #line) {
        if isInitialized {
            XCTAssertNotNil(MessagingInApp.shared.implementation, file: file, line: line)

            let eventListenerCallsCount = setEventListenerCallsCount ?? (givenEventListener != nil ? 1 : 0)
            XCTAssertEqual(implementationMock.setEventListenerCallsCount, eventListenerCallsCount, file: file, line: line)
        } else {
            XCTAssertNil(MessagingInApp.shared.implementation, file: file, line: line)
            XCTAssertFalse(implementationMock.mockCalled, file: file, line: line)
        }
    }
}
