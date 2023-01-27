@testable import CioMessagingInApp
@testable import CioTracking
@testable import Common
import Foundation
@testable import Gist
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

        assertModuleInitialized(isInitialized: true)
    }

    func test_initializeEventListener_givenSdkInitialized_expectModuleIsInitialized() {
        MessagingInApp.initialize(eventListener: InAppEventListenerMock())

        assertModuleInitialized(isInitialized: true)
    }

    func test_initializeOrganizationId_givenSdkInitialized_expectModuleIsInitialized() {
        MessagingInApp.initialize(organizationId: .random)

        assertModuleInitialized(isInitialized: true)
    }

    func test_initializeOrganizationIdEventListener_givenSdkInitialized_expectModuleIsInitialized() {
        MessagingInApp.initialize(organizationId: .random, eventListener: InAppEventListenerMock())

        assertModuleInitialized(isInitialized: true)
    }

    // MARK: initialize functions with SDK not initialized

    func test_initialize_givenSdkNotInitialized_expectModuleNotInitialized() {
        sdkInitializedUtilMock.underlyingIsInitlaized = false

        MessagingInApp.initialize()

        assertModuleInitialized(isInitialized: false)
    }

    func test_initializeEventListener_givenSdkNotInitialized_expectModuleNotInitialized() {
        sdkInitializedUtilMock.underlyingIsInitlaized = false

        MessagingInApp.initialize(eventListener: InAppEventListenerMock())

        assertModuleInitialized(isInitialized: false)
    }

    func test_initializeOrganizationId_givenSdkNotInitialized_expectModuleNotInitialized() {
        sdkInitializedUtilMock.underlyingIsInitlaized = false

        MessagingInApp.initialize(organizationId: .random)

        assertModuleInitialized(isInitialized: false)
    }

    func test_initializeOrganizationIdEventListener_givenSdkNotInitialized_expectModuleNotInitialized() {
        sdkInitializedUtilMock.underlyingIsInitlaized = false

        MessagingInApp.initialize(organizationId: .random, eventListener: InAppEventListenerMock())

        assertModuleInitialized(isInitialized: false)
    }

    func test_initialize_noEventListener_expectCallModuleInitializeCode() {
        MessagingInApp.initialize(organizationId: String.random, eventListener: nil, implementation: implementationMock, sdkInitializedUtil: sdkInitializedUtilMock)

        XCTAssertEqual(hooksMock.addCallsCount, 1)
        XCTAssertEqual(hooksMock.addReceivedArguments?.key, .messagingInApp)
        XCTAssertEqual(implementationMock.initializeCallsCount, 1)
        XCTAssertEqual(implementationMock.initializeEventListenerCallsCount, 0)
    }

    func test_initialize_givenEventListener_expectCallModuleInitializeCode() {
        MessagingInApp.initialize(organizationId: String.random, eventListener: InAppEventListenerMock(), implementation: implementationMock, sdkInitializedUtil: sdkInitializedUtilMock)

        XCTAssertEqual(hooksMock.addCallsCount, 1)
        XCTAssertEqual(hooksMock.addReceivedArguments?.key, .messagingInApp)
        XCTAssertEqual(implementationMock.initializeCallsCount, 0)
        XCTAssertEqual(implementationMock.initializeEventListenerCallsCount, 1)
    }

    func test_initialize_sdkNotInitialized_expectInAppModuleNotInitialized() {
        sdkInitializedUtilMock.underlyingPostInitializedData = nil // the SDK is no longer initialized

        MessagingInApp.initialize(organizationId: String.random, eventListener: nil, implementation: nil, sdkInitializedUtil: sdkInitializedUtilMock)

        XCTAssertFalse(hooksMock.addCalled)
        XCTAssertFalse(hooksMock.mockCalled)
        XCTAssertFalse(implementationMock.mockCalled)
    }
}

extension MessagingInAppTest {
    private func assertModuleInitialized(isInitialized: Bool, file: StaticString = #file, line: UInt = #line) {
        if isInitialized {
            XCTAssertEqual(hooksMock.addCallsCount, 1, file: file, line: line)
            XCTAssertEqual(hooksMock.addReceivedArguments?.key, .messagingInApp, file: file, line: line)
        } else {
            XCTAssertFalse(hooksMock.addCalled, file: file, line: line)
            XCTAssertFalse(hooksMock.mockCalled, file: file, line: line)
        }
    }
}
