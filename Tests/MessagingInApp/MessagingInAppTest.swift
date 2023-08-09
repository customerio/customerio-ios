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
        MessagingInApp.shared = MessagingInApp(implementation: implementationMock, sdkInitializedUtil: sdkInitializedUtilMock)
    }

    override func tearDown() {
        super.tearDown()

        MessagingInApp.resetSharedInstance()
    }

    // MARK: initialize functions with SDK initialized

    func test_initialize_givenSdkInitialized_expectModuleIsInitialized() {
        MessagingInApp.initialize()

        assertModuleInitialized(isInitialized: true, givenEventListener: nil)
    }

    func test_initializeEventListener_givenSdkInitialized_expectModuleIsInitialized() {
        let givenListener = InAppEventListenerMock()

        MessagingInApp.initialize(eventListener: givenListener)

        assertModuleInitialized(isInitialized: true, givenEventListener: givenListener)
    }

    func test_initializeOrganizationId_givenSdkInitialized_expectModuleIsInitialized() {
        MessagingInApp.initialize(organizationId: .random)

        assertModuleInitialized(isInitialized: true, givenEventListener: nil)
    }

    // MARK: initialize functions with SDK not initialized

    func test_initialize_givenSdkNotInitialized_expectModuleNotInitialized() {
        sdkInitializedUtilMock.underlyingIsInitlaized = false

        MessagingInApp.initialize()

        assertModuleInitialized(isInitialized: false, givenEventListener: nil)
    }

    func test_initializeEventListener_givenSdkNotInitialized_expectModuleNotInitialized() {
        sdkInitializedUtilMock.underlyingIsInitlaized = false
        let givenListener = InAppEventListenerMock()

        MessagingInApp.initialize(eventListener: givenListener)

        assertModuleInitialized(isInitialized: false, givenEventListener: givenListener)
    }

    func test_initializeOrganizationId_givenSdkNotInitialized_expectModuleNotInitialized() {
        sdkInitializedUtilMock.underlyingIsInitlaized = false

        MessagingInApp.initialize(organizationId: .random)

        assertModuleInitialized(isInitialized: false, givenEventListener: nil)
    }
}

extension MessagingInAppTest {
    private func assertModuleInitialized(isInitialized: Bool, givenEventListener: InAppEventListener?, file: StaticString = #file, line: UInt = #line) {
        if isInitialized {
            XCTAssertEqual(hooksMock.addCallsCount, 1, file: file, line: line)
            XCTAssertEqual(hooksMock.addReceivedArguments?.key, .messagingInApp, file: file, line: line)

            if givenEventListener != nil {
                XCTAssertEqual(implementationMock.initializeEventListenerCallsCount, 1)
                XCTAssertEqual(implementationMock.initializeCallsCount, 0)
            } else {
                XCTAssertEqual(implementationMock.initializeEventListenerCallsCount, 0)
                XCTAssertEqual(implementationMock.initializeCallsCount, 1)
            }
        } else {
            XCTAssertFalse(hooksMock.addCalled, file: file, line: line)
            XCTAssertFalse(hooksMock.mockCalled, file: file, line: line)
            XCTAssertFalse(implementationMock.initializeCalled && implementationMock.initializeEventListenerCalled)
        }
    }
}
