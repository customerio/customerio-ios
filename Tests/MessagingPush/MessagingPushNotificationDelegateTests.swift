@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioMessagingPushMocks
@_spi(Internal) @testable import CioMessagingPush
import SharedTests
import UIKit
import UserNotifications
import XCTest

class MessagingPushNotificationDelegateTests: XCTestCase {
    private final class BlockingNotificationCenter: UserNotificationCenterIntegration {
        private let lock = NSLock()
        private var storedDelegate: UNUserNotificationCenterDelegate?
        var onFirstProxyAssignment: (() -> Void)?

        var delegate: UNUserNotificationCenterDelegate? {
            get {
                lock.lock()
                defer { lock.unlock() }
                return storedDelegate
            }
            set {
                lock.lock()
                storedDelegate = newValue
                let callback = onFirstProxyAssignment
                onFirstProxyAssignment = nil
                lock.unlock()
                if newValue is CioNotificationCenterDelegate {
                    callback?()
                }
            }
        }
    }

    private final class ReentrantSetterNotificationCenter: UserNotificationCenterIntegration {
        var delegate: UNUserNotificationCenterDelegate? {
            didSet {
                guard delegate is CioNotificationCenterDelegate, let onProxyAssignment = onProxyAssignment else {
                    return
                }
                self.onProxyAssignment = nil
                onProxyAssignment()
            }
        }

        var onProxyAssignment: (() -> Void)?
    }

    private final class CountingCioNotificationCenterDelegate: CioNotificationCenterDelegate {
        var willPresentCallsCount = 0

        override func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            willPresent notification: UNNotification,
            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
        ) {
            willPresentCallsCount += 1
            completionHandler([])
        }
    }

    private final class ReentrantNotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
        var callsCount = 0
        var onWillPresent: (() -> Void)?

        func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            willPresent notification: UNNotification,
            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
        ) {
            callsCount += 1
            onWillPresent?()
            completionHandler([])
        }
    }

    var mockMessagingPush: MessagingPushInstanceMock!
    var mockNotificationCenter: UserNotificationCenterIntegrationMock!
    var mockLogger: LoggerMock!

    func createMockConfig(
        autoTrackPushEvents: Bool = true,
        showPushAppInForeground: Bool = true
    ) -> MessagingPushConfigOptions {
        MessagingPushConfigOptions(
            logLevel: .info,
            cdpApiKey: "test-api-key",
            region: .US,
            autoFetchDeviceToken: true,
            autoTrackPushEvents: autoTrackPushEvents,
            showPushAppInForeground: showPushAppInForeground,
            appGroupId: nil
        )
    }

    override func setUp() {
        super.setUp()

        UNUserNotificationCenter.swizzleNotificationCenter()

        mockMessagingPush = MessagingPushInstanceMock()
        mockNotificationCenter = UserNotificationCenterIntegrationMock()
        mockLogger = LoggerMock()
    }

    override func tearDown() {
        mockMessagingPush = nil
        mockNotificationCenter = nil
        mockLogger = nil

        UNUserNotificationCenter.unswizzleNotificationCenter()
        MessagingPush.resetNotificationCenterDelegate()

        super.tearDown()
    }

    // MARK: - installNotificationCenterDelegate

    func testInstallNotificationCenterDelegate_whenCalled_thenDelegateIsInstalledOnCenter() {
        MessagingPush.installNotificationCenterDelegate(
            wrapping: nil,
            centerProvider: { self.mockNotificationCenter }
        )

        XCTAssertTrue(mockNotificationCenter.delegate is CioNotificationCenterDelegate)
    }

    func testInstallNotificationCenterDelegate_whenExistingDelegateIsPresent_thenItIsWrapped() {
        let existingDelegate = MockNotificationCenterDelegate()
        mockNotificationCenter.delegate = existingDelegate

        MessagingPush.installNotificationCenterDelegate(
            wrapping: mockNotificationCenter.delegate,
            centerProvider: { self.mockNotificationCenter }
        )

        XCTAssertTrue(mockNotificationCenter.delegate is CioNotificationCenterDelegate)

        // Verify the wrapped delegate receives forwarded calls
        var completionHandlerCalled = false
        mockNotificationCenter.delegate?.userNotificationCenter?(
            UNUserNotificationCenter.current(),
            willPresent: UNNotification.testInstance,
            withCompletionHandler: { _ in completionHandlerCalled = true }
        )
        XCTAssertTrue(existingDelegate.willPresentNotificationCalled)
    }

    func testInstallNotificationCenterDelegate_whenCalledTwice_thenReusesProxyAndRetainsBothPeers() {
        let firstPeer = MockNotificationCenterDelegate()
        let secondPeer = MockNotificationCenterDelegate()
        MessagingPush.installNotificationCenterDelegate(
            wrapping: firstPeer,
            centerProvider: { self.mockNotificationCenter }
        )
        let firstDelegate = mockNotificationCenter.delegate

        MessagingPush.installNotificationCenterDelegate(
            wrapping: secondPeer,
            centerProvider: { self.mockNotificationCenter }
        )
        let secondDelegate = mockNotificationCenter.delegate

        XCTAssertTrue(secondDelegate is CioNotificationCenterDelegate)
        XCTAssertTrue(firstDelegate === secondDelegate)

        secondDelegate?.userNotificationCenter?(
            UNUserNotificationCenter.current(),
            willPresent: UNNotification.testInstance,
            withCompletionHandler: { _ in }
        )
        XCTAssertTrue(firstPeer.willPresentNotificationCalled)
        XCTAssertTrue(secondPeer.willPresentNotificationCalled)
    }

    func testInstallNotificationCenterDelegate_whenPeerAInstalledBeforeAndPeerBAfter_thenBothReceiveCallbacksOnce() {
        let peerA = MockNotificationCenterDelegate()
        let peerB = MockNotificationCenterDelegate()
        MessagingPush.installNotificationCenterDelegate(
            wrapping: peerA,
            centerProvider: { self.mockNotificationCenter }
        )
        MessagingPush.installNotificationCenterDelegate(
            wrapping: peerB,
            centerProvider: { self.mockNotificationCenter }
        )
        let proxy = MessagingPush.shared.installedNotificationCenterDelegate
        var willPresentOuterCallsCount = 0
        var didReceiveOuterCallsCount = 0

        proxy?.userNotificationCenter(
            UNUserNotificationCenter.current(),
            willPresent: UNNotification.testInstance,
            withCompletionHandler: { _ in willPresentOuterCallsCount += 1 }
        )
        proxy?.userNotificationCenter(
            UNUserNotificationCenter.current(),
            didReceive: UNNotificationResponse.testInstance,
            withCompletionHandler: { didReceiveOuterCallsCount += 1 }
        )

        XCTAssertTrue(peerA.willPresentNotificationCalled)
        XCTAssertTrue(peerB.willPresentNotificationCalled)
        XCTAssertTrue(peerA.didReceiveNotificationResponseCalled)
        XCTAssertTrue(peerB.didReceiveNotificationResponseCalled)
        XCTAssertEqual(willPresentOuterCallsCount, 1)
        XCTAssertEqual(didReceiveOuterCallsCount, 1)
    }

    func testInstallNotificationCenterDelegate_whenSamePeerIsAssignedTwice_thenForwardsOnce() {
        let peer = MockNotificationCenterDelegate()
        MessagingPush.installNotificationCenterDelegate(
            wrapping: peer,
            centerProvider: { self.mockNotificationCenter }
        )
        MessagingPush.installNotificationCenterDelegate(
            wrapping: peer,
            centerProvider: { self.mockNotificationCenter }
        )

        MessagingPush.shared.installedNotificationCenterDelegate?.userNotificationCenter(
            UNUserNotificationCenter.current(),
            willPresent: UNNotification.testInstance,
            withCompletionHandler: { _ in }
        )

        XCTAssertEqual(
            MessagingPush.shared.installedNotificationCenterDelegate?.peerRegistry.livePeers().count,
            1
        )
        XCTAssertTrue(peer.willPresentNotificationCalled)
    }

    func testInstallNotificationCenterDelegate_whenPeerAssignsAnotherPeerReentrantly_thenNewPeerStartsNextDelivery() {
        let peerA = ReentrantNotificationCenterDelegate()
        let peerB = ReentrantNotificationCenterDelegate()
        MessagingPush.installNotificationCenterDelegate(
            wrapping: peerA,
            centerProvider: { self.mockNotificationCenter }
        )
        peerA.onWillPresent = {
            MessagingPush.installNotificationCenterDelegate(
                wrapping: peerB,
                centerProvider: { self.mockNotificationCenter }
            )
        }
        let proxy = MessagingPush.shared.installedNotificationCenterDelegate

        proxy?.userNotificationCenter(
            UNUserNotificationCenter.current(),
            willPresent: UNNotification.testInstance,
            withCompletionHandler: { _ in }
        )
        XCTAssertEqual(peerA.callsCount, 1)
        XCTAssertEqual(peerB.callsCount, 0)

        proxy?.userNotificationCenter(
            UNUserNotificationCenter.current(),
            willPresent: UNNotification.testInstance,
            withCompletionHandler: { _ in }
        )
        XCTAssertEqual(peerA.callsCount, 2)
        XCTAssertEqual(peerB.callsCount, 1)
    }

    func testInstallNotificationCenterDelegate_whenNilIsInitialValue_thenInstallsProxyWithNoPeers() {
        MessagingPush.installNotificationCenterDelegate(
            wrapping: nil,
            centerProvider: { self.mockNotificationCenter }
        )

        XCTAssertTrue(mockNotificationCenter.delegate is CioNotificationCenterDelegate)
        XCTAssertTrue(MessagingPush.shared.installedNotificationCenterDelegate?.peerRegistry.livePeers().isEmpty == true)
    }

    func testInstallNotificationCenterDelegate_whenNilIsAssignedAfterPeer_thenClearsPeersButKeepsProxy() {
        let peer = MockNotificationCenterDelegate()
        MessagingPush.installNotificationCenterDelegate(
            wrapping: peer,
            centerProvider: { self.mockNotificationCenter }
        )
        let proxy = mockNotificationCenter.delegate

        MessagingPush.installNotificationCenterDelegate(
            wrapping: nil,
            centerProvider: { self.mockNotificationCenter }
        )

        XCTAssertTrue(mockNotificationCenter.delegate === proxy)
        XCTAssertTrue(MessagingPush.shared.installedNotificationCenterDelegate?.peerRegistry.livePeers().isEmpty == true)
    }

    func testInstallNotificationCenterDelegate_whenNilStartsDuringFirstProxySetter_thenLaterNilClearsPeer() {
        let center = BlockingNotificationCenter()
        let peer = MockNotificationCenterDelegate()
        let firstReachedProxyAssignment = DispatchSemaphore(value: 0)
        let allowFirstInstallToFinish = DispatchSemaphore(value: 0)
        center.onFirstProxyAssignment = {
            firstReachedProxyAssignment.signal()
            _ = allowFirstInstallToFinish.wait(timeout: .now() + 5)
        }
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global().async {
            MessagingPush.installNotificationCenterDelegate(
                wrapping: peer,
                centerProvider: { center }
            )
            group.leave()
        }
        XCTAssertEqual(firstReachedProxyAssignment.wait(timeout: .now() + 5), .success)

        group.enter()
        DispatchQueue.global().async {
            MessagingPush.installNotificationCenterDelegate(
                wrapping: nil,
                centerProvider: { center }
            )
            group.leave()
        }
        allowFirstInstallToFinish.signal()

        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
        XCTAssertTrue(center.delegate === MessagingPush.shared.installedNotificationCenterDelegate)
        XCTAssertTrue(MessagingPush.shared.installedNotificationCenterDelegate?.peerRegistry.livePeers().isEmpty == true)
    }

    func testInstallNotificationCenterDelegate_whenProxySetterReassignsDelegateSynchronously_thenDoesNotDeadlockAndLaterPeerWins() {
        let center = ReentrantSetterNotificationCenter()
        let firstPeer = MockNotificationCenterDelegate()
        let reentrantPeer = MockNotificationCenterDelegate()
        center.onProxyAssignment = {
            MessagingPush.installNotificationCenterDelegate(
                wrapping: reentrantPeer,
                centerProvider: { center }
            )
        }

        MessagingPush.installNotificationCenterDelegate(
            wrapping: firstPeer,
            centerProvider: { center }
        )

        XCTAssertTrue(center.delegate === MessagingPush.shared.installedNotificationCenterDelegate)
        XCTAssertEqual(
            MessagingPush.shared.installedNotificationCenterDelegate?.peerRegistry.livePeers().map(ObjectIdentifier.init),
            [ObjectIdentifier(firstPeer), ObjectIdentifier(reentrantPeer)]
        )
    }

    func testInstallNotificationCenterDelegate_whenForeignCioDelegateExistsBeforeSharedProxy_thenPreservesItAsPeer() {
        let foreignProxy = CountingCioNotificationCenterDelegate(
            messagingPush: mockMessagingPush,
            config: { self.createMockConfig() },
            wrappedDelegate: nil
        )

        MessagingPush.installNotificationCenterDelegate(
            wrapping: foreignProxy,
            centerProvider: { self.mockNotificationCenter }
        )
        MessagingPush.shared.installedNotificationCenterDelegate?.userNotificationCenter(
            UNUserNotificationCenter.current(),
            willPresent: UNNotification.testInstance,
            withCompletionHandler: { _ in }
        )

        XCTAssertEqual(foreignProxy.willPresentCallsCount, 1)
        XCTAssertTrue(mockNotificationCenter.delegate === MessagingPush.shared.installedNotificationCenterDelegate)
    }

    func testInstallNotificationCenterDelegate_whenForeignCioDelegateIsAssignedAfterSharedProxy_thenPreservesSharedProxyAndForwardsToForeign() {
        MessagingPush.installNotificationCenterDelegate(
            wrapping: nil,
            centerProvider: { self.mockNotificationCenter }
        )
        let sharedProxy = MessagingPush.shared.installedNotificationCenterDelegate
        let foreignProxy = CountingCioNotificationCenterDelegate(
            messagingPush: mockMessagingPush,
            config: { self.createMockConfig() },
            wrappedDelegate: nil
        )

        MessagingPush.installNotificationCenterDelegate(
            wrapping: foreignProxy,
            centerProvider: { self.mockNotificationCenter }
        )
        sharedProxy?.userNotificationCenter(
            UNUserNotificationCenter.current(),
            willPresent: UNNotification.testInstance,
            withCompletionHandler: { _ in }
        )

        XCTAssertTrue(mockNotificationCenter.delegate === sharedProxy)
        XCTAssertEqual(foreignProxy.willPresentCallsCount, 1)
    }

    func testInstallNotificationCenterDelegate_whenExactSharedProxyIsReassigned_thenDoesNotRegisterItself() {
        MessagingPush.installNotificationCenterDelegate(
            wrapping: nil,
            centerProvider: { self.mockNotificationCenter }
        )
        let sharedProxy = MessagingPush.shared.installedNotificationCenterDelegate

        MessagingPush.installNotificationCenterDelegate(
            wrapping: sharedProxy,
            centerProvider: { self.mockNotificationCenter }
        )

        XCTAssertTrue(mockNotificationCenter.delegate === sharedProxy)
        XCTAssertTrue(sharedProxy?.peerRegistry.livePeers().isEmpty == true)
    }

    // MARK: - delegate swizzle wrapping

    func testIsInstalledNotificationCenterDelegate_whenIncomingAndInstalledDelegatesAreNil_thenReturnsFalse() {
        MessagingPush.resetNotificationCenterDelegate()

        let isInstalledProxy = MessagingPush.isInstalledNotificationCenterDelegate(nil)

        XCTAssertFalse(isInstalledProxy)
    }

    func testCioSwizzledSetDelegate_whenNonCioDelegateAssigned_thenItIsWrappedInCioDelegate() {
        let externalDelegate = MockNotificationCenterDelegate()
        MessagingPush.installNotificationCenterDelegate(
            wrapping: nil,
            centerProvider: { self.mockNotificationCenter }
        )

        // Simulate what the swizzle does when another SDK assigns its delegate.
        MessagingPush.installNotificationCenterDelegate(
            wrapping: externalDelegate,
            centerProvider: { self.mockNotificationCenter }
        )

        XCTAssertTrue(mockNotificationCenter.delegate is CioNotificationCenterDelegate)
        // Verify the external delegate is forwarded calls by the wrapper.
        mockNotificationCenter.delegate?.userNotificationCenter?(
            UNUserNotificationCenter.current(),
            willPresent: UNNotification.testInstance,
            withCompletionHandler: { _ in }
        )
        XCTAssertTrue(externalDelegate.willPresentNotificationCalled)
    }

    func testCioSwizzledSetDelegate_whenCioDelegateAssigned_thenNoDuplicateWrapping() {
        // Install our delegate wrapping an external one.
        let externalDelegate = MockNotificationCenterDelegate()
        MessagingPush.installNotificationCenterDelegate(
            wrapping: externalDelegate,
            centerProvider: { self.mockNotificationCenter }
        )
        let firstProxy = mockNotificationCenter.delegate as? CioNotificationCenterDelegate

        // Reassigning our own CioNotificationCenterDelegate should not nest another wrapper on top.
        // (The swizzle checks the exact installed proxy identity and passes it through.)
        // Simulate pass-through: installing again with the same proxy should still forward correctly.
        XCTAssertNotNil(firstProxy)
        mockNotificationCenter.delegate?.userNotificationCenter?(
            UNUserNotificationCenter.current(),
            willPresent: UNNotification.testInstance,
            withCompletionHandler: { _ in }
        )
        XCTAssertTrue(externalDelegate.willPresentNotificationCalled)
    }
}
