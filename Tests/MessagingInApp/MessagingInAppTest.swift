@testable import CioInternalCommon
@testable import CioMessagingInApp
@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class MessagingInAppTest: UnitTest {
    private let hooksMock = HooksManagerMock()
    private let implementationMock = MessagingInAppInstanceMock()
    private let sdkInitializedUtilMock = SdkInitializedUtilMock()

    override func setUp() {
        super.setUp()

        // This is where we inject the DI graph into our tests
        sdkInitializedUtilMock.isInitlaized = true
        sdkInitializedUtilMock.underlyingPostInitializedData = (siteId: testSiteId, diGraph: diGraph)

        // This is where we inject the DI graph into our tests
        sdkInitializedUtilMock.underlyingPostInitializedData = (siteId: testSiteId, diGraph: diGraph)

        diGraph.override(value: hooksMock, forType: HooksManager.self)

        // Sets default shared instance, which injects the DI graph
//        MessagingInApp.shared = MessagingInApp(implementation: implementationMock)
    }

    override func tearDown() {
        super.tearDown()

        MessagingInApp.resetSharedInstance()
    }

    // MARK: initialize functions with Module initialized

    func test_initialize_givenModuleInitialized_expectModuleIsInitialized() {
        MessagingInApp.shared = MessagingInApp(implementation: implementationMock)
        MessagingInApp.initialize(siteId: .random, region: .US)

        assertModuleInitialized(isInitialized: true, givenEventListener: nil)
    }

    func test_setEventListener_givenModuleInitialized_expectListenerIsSet() {
        let givenListener = InAppEventListenerMock()
        MessagingInApp.shared = MessagingInApp(implementation: implementationMock)
        MessagingInApp.initialize(siteId: .random, region: .US)
        MessagingInApp.shared.setEventListener(givenListener)

        assertModuleInitialized(isInitialized: true, givenEventListener: givenListener)
    }

    func test_clearEventListener_givenModuleInitialized_expectListenerIsCleared() {
        let givenListener = InAppEventListenerMock()

        MessagingInApp.initialize(siteId: .random, region: .US)
        MessagingInApp.shared.setEventListener(givenListener)
        // clear event listener
        MessagingInApp.shared.setEventListener(nil)

        assertModuleInitialized(isInitialized: true, givenEventListener: nil)
    }

    // MARK: initialize functions with Module not initialized

    func test_setEventListener_givenModuleNotInitialized_expectListenerNotSet() {
        let givenListener = InAppEventListenerMock()

        MessagingInApp.shared.setEventListener(givenListener)

        assertModuleInitialized(isInitialized: false, givenEventListener: nil)
    }

    // MARK: initialize functions with SDK initialized

    func test_initialize_givenSdkInitialized_expectModuleIsInitialized() {
        MessagingInApp.initialize(siteId: .random, region: .US)

        assertModuleInitialized(isInitialized: true, givenEventListener: nil)
    }

    // MARK: initialize functions with SDK not initialized

    func test_initialize_givenSdkNotInitialized_expectModuleIsInitialized() {
        sdkInitializedUtilMock.underlyingIsInitlaized = false

        MessagingInApp.initialize(siteId: .random, region: .US)

        assertModuleInitialized(isInitialized: true, givenEventListener: nil)
    }
}

extension MessagingInAppTest {
    private func assertModuleInitialized(isInitialized: Bool, givenEventListener: InAppEventListener?, file: StaticString = #file, line: UInt = #line) {
        if isInitialized {
            if givenEventListener != nil {
                XCTAssertEqual(implementationMock.setEventListenerCallsCount, 1)
            } else {
                XCTAssertEqual(implementationMock.setEventListenerCallsCount, 0)
            }
        } else {
            XCTAssertFalse(implementationMock.setEventListenerCalled)
        }
    }
}
