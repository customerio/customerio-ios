@testable import CioInternalCommonMocks
@testable import CioMessagingPushMocks
@_spi(Internal) @testable import CioMessagingPush
import SharedTests
import UIKit
import UserNotifications
import XCTest

final class CioNotificationDelegateMultiPeerTests: XCTestCase {
    private final class CompletionCapture {
        var willPresent: ((UNNotificationPresentationOptions) -> Void)?
        var didReceive: (() -> Void)?

        func captureWillPresent(
            _ completion: @escaping (UNNotificationPresentationOptions) -> Void
        ) {
            willPresent = completion
        }

        func captureDidReceive(_ completion: @escaping () -> Void) {
            didReceive = completion
        }
    }

    private final class Peer: NSObject, UNUserNotificationCenterDelegate {
        var implementsWillPresent = true
        var implementsDidReceive = true
        var implementsOpenSettings = true
        var willPresentCallsCount = 0
        var didReceiveCallsCount = 0
        var openSettingsCallsCount = 0
        var presentationOptions: UNNotificationPresentationOptions = []
        var completionCapture: CompletionCapture?
        var discardsDidReceiveCompletion = false
        var onWillPresentInvocation: (() -> Void)?

        override func responds(to selector: Selector!) -> Bool {
            switch selector {
            case #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:withCompletionHandler:)):
                return implementsWillPresent
            case #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:)):
                return implementsDidReceive
            case #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:openSettingsFor:)):
                return implementsOpenSettings
            default:
                return super.responds(to: selector)
            }
        }

        func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            willPresent notification: UNNotification,
            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
        ) {
            willPresentCallsCount += 1
            onWillPresentInvocation?()
            if let completionCapture = completionCapture {
                completionCapture.captureWillPresent(completionHandler)
            } else {
                completionHandler(presentationOptions)
            }
        }

        func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            didReceive response: UNNotificationResponse,
            withCompletionHandler completionHandler: @escaping () -> Void
        ) {
            didReceiveCallsCount += 1
            guard !discardsDidReceiveCompletion else { return }
            if let completionCapture = completionCapture {
                completionCapture.captureDidReceive(completionHandler)
            } else {
                completionHandler()
            }
        }

        func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            openSettingsFor notification: UNNotification?
        ) {
            openSettingsCallsCount += 1
        }
    }

    private final class CustomizingCioNotificationCenterDelegate: CioNotificationCenterDelegate {
        var didReceiveCallsCount = 0
        var callsSuperAsynchronously = false

        override func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            didReceive response: UNNotificationResponse,
            withCompletionHandler completionHandler: @escaping () -> Void
        ) {
            didReceiveCallsCount += 1
            let callSuper = {
                super.userNotificationCenter(
                    center,
                    didReceive: response,
                    withCompletionHandler: completionHandler
                )
            }
            if callsSuperAsynchronously {
                DispatchQueue.global().async(execute: callSuper)
            } else {
                callSuper()
            }
        }
    }

    private final class NonForwardingCioDelegate: CioNotificationCenterDelegate {
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

    private final class ChainedNotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
        let previousDelegate: UNUserNotificationCenterDelegate
        var willPresentCallsCount = 0
        var didReceiveCallsCount = 0
        var openSettingsCallsCount = 0
        var forwardsWillPresentAsynchronously = false
        var forwardsDidReceiveAsynchronously = false
        var forwardsOpenSettingsAsynchronously = false
        var onAsyncWillPresentForwarded: (() -> Void)?
        var onAsyncOpenSettingsForwarded: (() -> Void)?

        init(previousDelegate: UNUserNotificationCenterDelegate) {
            self.previousDelegate = previousDelegate
        }

        func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            willPresent notification: UNNotification,
            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
        ) {
            willPresentCallsCount += 1
            let forward = {
                _ = self.previousDelegate.userNotificationCenter?(
                    center,
                    willPresent: notification,
                    withCompletionHandler: completionHandler
                )
            }
            if forwardsWillPresentAsynchronously {
                DispatchQueue.global().async {
                    forward()
                    self.onAsyncWillPresentForwarded?()
                }
            } else {
                forward()
            }
        }

        func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            didReceive response: UNNotificationResponse,
            withCompletionHandler completionHandler: @escaping () -> Void
        ) {
            didReceiveCallsCount += 1
            let forward: () -> Void = {
                _ = self.previousDelegate.userNotificationCenter?(
                    center,
                    didReceive: response,
                    withCompletionHandler: completionHandler
                )
            }
            if forwardsDidReceiveAsynchronously {
                DispatchQueue.global().async(execute: forward)
            } else {
                forward()
            }
        }

        func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            openSettingsFor notification: UNNotification?
        ) {
            openSettingsCallsCount += 1
            let forward = {
                _ = self.previousDelegate.userNotificationCenter?(center, openSettingsFor: notification)
            }
            if forwardsOpenSettingsAsynchronously {
                DispatchQueue.global().async {
                    forward()
                    self.onAsyncOpenSettingsForwarded?()
                }
            } else {
                forward()
            }
        }
    }

    private var registry: NotificationDelegatePeerRegistryImpl!
    private var pushHandlingCallsCount = 0
    private var delegate: CioNotificationCenterDelegate!

    override func setUp() {
        super.setUp()
        UNUserNotificationCenter.swizzleNotificationCenter()
        registry = NotificationDelegatePeerRegistryImpl()
        delegate = makeDelegate(showPushAppInForeground: true)
    }

    override func tearDown() {
        delegate = nil
        registry = nil
        UNUserNotificationCenter.unswizzleNotificationCenter()
        super.tearDown()
    }

    func testWillPresent_whenSinglePeerReturnsEmpty_thenPreservesPeerResultInsteadOfCioDefault() {
        let peer = Peer()
        registry.register(peer)
        var result: UNNotificationPresentationOptions?

        delegate.userNotificationCenter(
            UNUserNotificationCenter.current(),
            willPresent: UNNotification.testInstance,
            withCompletionHandler: { result = $0 }
        )

        XCTAssertEqual(result, [])
        XCTAssertEqual(peer.willPresentCallsCount, 1)
    }

    func testWillPresent_whenSeveralPeersImplementSelector_thenUnionsTheirOptions() {
        let first = Peer()
        first.presentationOptions = [.badge, .sound]
        let second = Peer()
        second.presentationOptions = [.alert]
        registry.register(first)
        registry.register(second)
        var result: UNNotificationPresentationOptions?

        delegate.userNotificationCenter(
            UNUserNotificationCenter.current(),
            willPresent: UNNotification.testInstance,
            withCompletionHandler: { result = $0 }
        )

        XCTAssertEqual(result, [.badge, .sound, .alert])
        XCTAssertEqual(first.willPresentCallsCount, 1)
        XCTAssertEqual(second.willPresentCallsCount, 1)
    }

    func testWillPresent_whenNoPeerImplementsSelector_thenUsesCioConfiguredFallback() {
        let peer = Peer()
        peer.implementsWillPresent = false
        registry.register(peer)
        var result: UNNotificationPresentationOptions?

        delegate.userNotificationCenter(
            UNUserNotificationCenter.current(),
            willPresent: UNNotification.testInstance,
            withCompletionHandler: { result = $0 }
        )

        if #available(iOS 14.0, *) {
            XCTAssertEqual(result, [.list, .banner, .badge, .sound])
        } else {
            XCTAssertEqual(result, [.alert, .badge, .sound])
        }
        XCTAssertEqual(peer.willPresentCallsCount, 0)
    }

    func testWillPresent_whenCompletedNotificationReturns_thenDoesNotFanOutTwice() {
        let peer = Peer()
        registry.register(peer)
        let notification = UNNotification.testInstance
        var outerCallsCount = 0

        delegate.userNotificationCenter(
            UNUserNotificationCenter.current(),
            willPresent: notification,
            withCompletionHandler: { _ in outerCallsCount += 1 }
        )
        delegate.userNotificationCenter(
            UNUserNotificationCenter.current(),
            willPresent: notification,
            withCompletionHandler: { _ in outerCallsCount += 1 }
        )

        XCTAssertEqual(peer.willPresentCallsCount, 1)
        XCTAssertEqual(outerCallsCount, 2)
    }

    func testFanOut_whenPeersCompleteAsyncOutOfOrderAndDuplicate_thenOuterHandlersCompleteOnce() {
        let first = Peer()
        let second = Peer()
        let firstCapture = CompletionCapture()
        let secondCapture = CompletionCapture()
        first.completionCapture = firstCapture
        second.completionCapture = secondCapture
        registry.register(first)
        registry.register(second)
        var willPresentOuterCallsCount = 0
        var didReceiveOuterCallsCount = 0
        var presentationOptions: UNNotificationPresentationOptions?

        delegate.userNotificationCenter(
            UNUserNotificationCenter.current(),
            willPresent: UNNotification.testInstance,
            withCompletionHandler: {
                willPresentOuterCallsCount += 1
                presentationOptions = $0
            }
        )
        delegate.userNotificationCenter(
            UNUserNotificationCenter.current(),
            didReceive: UNNotificationResponse.testInstance,
            withCompletionHandler: { didReceiveOuterCallsCount += 1 }
        )
        XCTAssertNotNil(firstCapture.willPresent)
        XCTAssertNotNil(secondCapture.willPresent)
        XCTAssertNotNil(firstCapture.didReceive)
        XCTAssertNotNil(secondCapture.didReceive)

        secondCapture.willPresent?([.sound])
        secondCapture.willPresent?([.badge])
        secondCapture.didReceive?()
        secondCapture.didReceive?()
        XCTAssertEqual(willPresentOuterCallsCount, 0)
        XCTAssertEqual(didReceiveOuterCallsCount, 0)

        firstCapture.willPresent?([.alert])
        firstCapture.didReceive?()

        XCTAssertEqual(willPresentOuterCallsCount, 1)
        XCTAssertEqual(didReceiveOuterCallsCount, 1)
        XCTAssertEqual(presentationOptions, [.sound, .alert])
        XCTAssertEqual(first.willPresentCallsCount, 1)
        XCTAssertEqual(second.willPresentCallsCount, 1)
        XCTAssertEqual(first.didReceiveCallsCount, 1)
        XCTAssertEqual(second.didReceiveCallsCount, 1)
        XCTAssertEqual(pushHandlingCallsCount, 1)
    }

    func testDidReceive_whenPeerDoesNotImplementSelector_thenSkipsPeerAndCompletesOuterOnce() {
        let missingSelectorPeer = Peer()
        missingSelectorPeer.implementsDidReceive = false
        let implementingPeer = Peer()
        registry.register(missingSelectorPeer)
        registry.register(implementingPeer)
        var outerCallsCount = 0

        delegate.userNotificationCenter(
            UNUserNotificationCenter.current(),
            didReceive: UNNotificationResponse.testInstance,
            withCompletionHandler: { outerCallsCount += 1 }
        )

        XCTAssertEqual(missingSelectorPeer.didReceiveCallsCount, 0)
        XCTAssertEqual(implementingPeer.didReceiveCallsCount, 1)
        XCTAssertEqual(outerCallsCount, 1)
        XCTAssertEqual(pushHandlingCallsCount, 1)
    }

    func testDidReceive_whenPeerDiscardsCompletion_thenCustomerIoHandlingStillRunsOnce() {
        let peer = Peer()
        peer.discardsDidReceiveCompletion = true
        registry.register(peer)
        let response = UNNotificationResponse.testInstance
        var outerCallsCount = 0

        delegate.userNotificationCenter(
            UNUserNotificationCenter.current(),
            didReceive: response,
            withCompletionHandler: { outerCallsCount += 1 }
        )
        delegate.userNotificationCenter(
            UNUserNotificationCenter.current(),
            didReceive: response,
            withCompletionHandler: { outerCallsCount += 1 }
        )

        XCTAssertEqual(peer.didReceiveCallsCount, 1)
        XCTAssertEqual(pushHandlingCallsCount, 1)
        XCTAssertEqual(outerCallsCount, 1)
    }

    func testDidReceive_whenCompletedResponseReturnsAfterAggregateCloses_thenDoesNotHandleOrFanOutTwice() {
        let peer = Peer()
        let capture = CompletionCapture()
        peer.completionCapture = capture
        registry.register(peer)
        let response = UNNotificationResponse.testInstance
        var outerCallsCount = 0

        delegate.userNotificationCenter(
            UNUserNotificationCenter.current(),
            didReceive: response,
            withCompletionHandler: { outerCallsCount += 1 }
        )
        capture.didReceive?()
        delegate.userNotificationCenter(
            UNUserNotificationCenter.current(),
            didReceive: response,
            withCompletionHandler: { outerCallsCount += 1 }
        )

        XCTAssertEqual(peer.didReceiveCallsCount, 1)
        XCTAssertEqual(pushHandlingCallsCount, 1)
        XCTAssertEqual(outerCallsCount, 2)
    }

    func testDidReceive_whenCioHandlingRegistersPeerReentrantly_thenNewPeerStartsNextDelivery() {
        let first = Peer()
        let addedByCioHandling = Peer()
        registry.register(first)
        let reentrantDelegate = CioNotificationCenterDelegate(
            messagingPush: MessagingPushInstanceMock(),
            config: { MessagingPushConfigBuilder().build() },
            peerRegistry: registry,
            handlePushResponse: { [registry] _, _ in
                registry?.register(addedByCioHandling)
            }
        )

        reentrantDelegate.userNotificationCenter(
            UNUserNotificationCenter.current(),
            didReceive: UNNotificationResponse.testInstance,
            withCompletionHandler: {}
        )
        XCTAssertEqual(first.didReceiveCallsCount, 1)
        XCTAssertEqual(addedByCioHandling.didReceiveCallsCount, 0)

        reentrantDelegate.userNotificationCenter(
            UNUserNotificationCenter.current(),
            didReceive: UNNotificationResponse.testInstance,
            withCompletionHandler: {}
        )
        XCTAssertEqual(first.didReceiveCallsCount, 2)
        XCTAssertEqual(addedByCioHandling.didReceiveCallsCount, 1)
    }

    func testWillPresent_whenPeerRegistersAnotherPeerReentrantly_thenNewPeerStartsOnNextDelivery() {
        let first = Peer()
        let addedReentrantly = Peer()
        first.onWillPresentInvocation = { [registry] in
            registry?.register(addedReentrantly)
        }
        registry.register(first)

        delegate.userNotificationCenter(
            UNUserNotificationCenter.current(),
            willPresent: UNNotification.testInstance,
            withCompletionHandler: { _ in }
        )
        XCTAssertEqual(first.willPresentCallsCount, 1)
        XCTAssertEqual(addedReentrantly.willPresentCallsCount, 0)

        delegate.userNotificationCenter(
            UNUserNotificationCenter.current(),
            willPresent: UNNotification.testInstance,
            withCompletionHandler: { _ in }
        )
        XCTAssertEqual(first.willPresentCallsCount, 2)
        XCTAssertEqual(addedReentrantly.willPresentCallsCount, 1)
    }

    func testWillPresent_whenOwnerReleasesAsyncPeer_thenDeliveryRetainsItUntilOuterReturnsOnly() {
        var peer: Peer? = Peer()
        weak var weakPeer = peer
        let capture = CompletionCapture()
        peer?.completionCapture = capture
        registry.register(peer)
        var outerCallsCount = 0

        delegate.userNotificationCenter(
            UNUserNotificationCenter.current(),
            willPresent: UNNotification.testInstance,
            withCompletionHandler: { _ in
                outerCallsCount += 1
                XCTAssertNotNil(weakPeer)
            }
        )
        peer = nil
        XCTAssertNotNil(weakPeer)

        capture.willPresent?([])

        XCTAssertEqual(outerCallsCount, 1)
        XCTAssertNil(weakPeer)
        XCTAssertTrue(registry.livePeers().isEmpty)
    }

    func testDidReceive_whenFixtureIsNotHandledByConcreteCioPath_thenStillForwardsToEveryPeer() {
        let first = Peer()
        let second = Peer()
        registry.register(first)
        registry.register(second)
        var outerCallsCount = 0

        delegate.userNotificationCenter(
            UNUserNotificationCenter.current(),
            didReceive: UNNotificationResponse.testInstance,
            withCompletionHandler: { outerCallsCount += 1 }
        )

        XCTAssertEqual(pushHandlingCallsCount, 1)
        XCTAssertEqual(first.didReceiveCallsCount, 1)
        XCTAssertEqual(second.didReceiveCallsCount, 1)
        XCTAssertEqual(outerCallsCount, 1)
    }

    func testDidReceive_whenPublicCioDelegateIsPeer_thenRunsCioHandlingOnceAndPreservesSubclassAndWrappedForwarding() {
        let foreignRegistry = NotificationDelegatePeerRegistryImpl()
        let foreignWrappedPeer = Peer()
        foreignRegistry.register(foreignWrappedPeer)
        var foreignPushHandlingCallsCount = 0
        let foreignCioDelegate = CustomizingCioNotificationCenterDelegate(
            messagingPush: MessagingPushInstanceMock(),
            config: { MessagingPushConfigBuilder().build() },
            peerRegistry: foreignRegistry,
            handlePushResponse: { _, _ in foreignPushHandlingCallsCount += 1 }
        )
        foreignCioDelegate.callsSuperAsynchronously = true
        registry.register(foreignCioDelegate)
        var outerCallsCount = 0
        let outerCompleted = expectation(description: "outer completion")

        delegate.userNotificationCenter(
            UNUserNotificationCenter.current(),
            didReceive: UNNotificationResponse.testInstance,
            withCompletionHandler: {
                outerCallsCount += 1
                outerCompleted.fulfill()
            }
        )
        wait(for: [outerCompleted], timeout: 1)

        XCTAssertEqual(pushHandlingCallsCount, 1)
        XCTAssertEqual(foreignPushHandlingCallsCount, 0)
        XCTAssertEqual(foreignCioDelegate.didReceiveCallsCount, 1)
        XCTAssertEqual(foreignWrappedPeer.didReceiveCallsCount, 1)
        XCTAssertEqual(outerCallsCount, 1)
    }

    func testFanOut_whenPublicCioPeerWrapsAlreadyRegisteredPeer_thenWrappedPeerReceivesEachCallbackOnce() {
        let wrappedPeer = Peer()
        let compatibilityDelegate = CioNotificationCenterDelegate(
            messagingPush: MessagingPushInstanceMock(),
            config: { MessagingPushConfigBuilder().build() },
            wrappedDelegate: wrappedPeer
        )
        registry.register(wrappedPeer)
        registry.register(compatibilityDelegate)
        var willPresentOuterCallsCount = 0
        var didReceiveOuterCallsCount = 0

        delegate.userNotificationCenter(
            UNUserNotificationCenter.current(),
            willPresent: UNNotification.testInstance,
            withCompletionHandler: { _ in willPresentOuterCallsCount += 1 }
        )
        delegate.userNotificationCenter(
            UNUserNotificationCenter.current(),
            didReceive: UNNotificationResponse.testInstance,
            withCompletionHandler: { didReceiveOuterCallsCount += 1 }
        )

        XCTAssertEqual(wrappedPeer.willPresentCallsCount, 1)
        XCTAssertEqual(wrappedPeer.didReceiveCallsCount, 1)
        XCTAssertEqual(willPresentOuterCallsCount, 1)
        XCTAssertEqual(didReceiveOuterCallsCount, 1)
        XCTAssertEqual(pushHandlingCallsCount, 1)
    }

    func testWillPresent_whenCioSubclassDoesNotCallSuper_thenDirectWrappedPeerIsNotDropped() {
        let wrappedPeer = Peer()
        let subclass = NonForwardingCioDelegate(
            messagingPush: MessagingPushInstanceMock(),
            config: { MessagingPushConfigBuilder().build() },
            wrappedDelegate: wrappedPeer
        )
        registry.register(wrappedPeer)
        registry.register(subclass)
        var outerCallsCount = 0

        delegate.userNotificationCenter(
            UNUserNotificationCenter.current(),
            willPresent: UNNotification.testInstance,
            withCompletionHandler: { _ in outerCallsCount += 1 }
        )

        XCTAssertEqual(wrappedPeer.willPresentCallsCount, 1)
        XCTAssertEqual(subclass.willPresentCallsCount, 1)
        XCTAssertEqual(outerCallsCount, 1)
    }

    func testDidReceive_whenOpaqueWrapperReachesForeignCioDelegate_thenCioHandlingRunsOnce() {
        let foreignWrappedPeer = Peer()
        var foreignPushHandlingCallsCount = 0
        let foreignCioDelegate = CioNotificationCenterDelegate(
            messagingPush: MessagingPushInstanceMock(),
            config: { MessagingPushConfigBuilder().build() },
            peerRegistry: {
                let foreignRegistry = NotificationDelegatePeerRegistryImpl()
                foreignRegistry.register(foreignWrappedPeer)
                return foreignRegistry
            }(),
            handlePushResponse: { _, _ in foreignPushHandlingCallsCount += 1 }
        )
        let opaqueWrapper = ChainedNotificationCenterDelegate(previousDelegate: foreignCioDelegate)
        registry.register(opaqueWrapper)
        var outerCallsCount = 0

        delegate.userNotificationCenter(
            UNUserNotificationCenter.current(),
            didReceive: UNNotificationResponse.testInstance,
            withCompletionHandler: { outerCallsCount += 1 }
        )

        XCTAssertEqual(pushHandlingCallsCount, 1)
        XCTAssertEqual(foreignPushHandlingCallsCount, 0)
        XCTAssertEqual(opaqueWrapper.didReceiveCallsCount, 1)
        XCTAssertEqual(foreignWrappedPeer.didReceiveCallsCount, 1)
        XCTAssertEqual(outerCallsCount, 1)
    }

    func testDidReceive_whenPeerIsInstalledAboveCioByEarlierSwizzler_thenSkipsPeerToAvoidForwardingCycle() {
        let installedForwardingPeer = Peer()
        let ordinaryPeer = Peer()
        registry.register(installedForwardingPeer)
        registry.register(ordinaryPeer)
        let delegateBelowEarlierSwizzler = CioNotificationCenterDelegate(
            messagingPush: MessagingPushInstanceMock(),
            config: { MessagingPushConfigBuilder().build() },
            peerRegistry: registry,
            handlePushResponse: { [weak self] _, _ in
                self?.pushHandlingCallsCount += 1
            },
            systemDelegate: { _ in installedForwardingPeer }
        )
        var outerCallsCount = 0

        delegateBelowEarlierSwizzler.userNotificationCenter(
            UNUserNotificationCenter.current(),
            didReceive: UNNotificationResponse.testInstance,
            withCompletionHandler: { outerCallsCount += 1 }
        )

        XCTAssertEqual(pushHandlingCallsCount, 1)
        XCTAssertEqual(installedForwardingPeer.didReceiveCallsCount, 0)
        XCTAssertEqual(ordinaryPeer.didReceiveCallsCount, 1)
        XCTAssertEqual(outerCallsCount, 1)
    }

    func testFanOut_whenPeerChainsBackToCioProxy_thenTerminatesCycleAndHandlesDeliveryOnce() {
        let chainedPeer = ChainedNotificationCenterDelegate(previousDelegate: delegate)
        chainedPeer.forwardsDidReceiveAsynchronously = true
        registry.register(chainedPeer)
        var willPresentOuterCallsCount = 0
        var willPresentOptions: UNNotificationPresentationOptions?
        var didReceiveOuterCallsCount = 0
        let didReceiveCompleted = expectation(description: "didReceive aggregate completed")

        delegate.userNotificationCenter(
            UNUserNotificationCenter.current(),
            willPresent: UNNotification.testInstance,
            withCompletionHandler: {
                willPresentOptions = $0
                willPresentOuterCallsCount += 1
            }
        )
        delegate.userNotificationCenter(
            UNUserNotificationCenter.current(),
            didReceive: UNNotificationResponse.testInstance,
            withCompletionHandler: {
                didReceiveOuterCallsCount += 1
                didReceiveCompleted.fulfill()
            }
        )
        delegate.userNotificationCenter(
            UNUserNotificationCenter.current(),
            openSettingsFor: UNNotification.testInstance
        )
        wait(for: [didReceiveCompleted], timeout: 1)

        XCTAssertEqual(pushHandlingCallsCount, 1)
        XCTAssertEqual(chainedPeer.willPresentCallsCount, 1)
        XCTAssertEqual(chainedPeer.didReceiveCallsCount, 1)
        XCTAssertEqual(chainedPeer.openSettingsCallsCount, 1)
        XCTAssertEqual(willPresentOuterCallsCount, 1)
        if #available(iOS 14.0, *) {
            XCTAssertEqual(willPresentOptions, [.list, .banner, .badge, .sound])
        } else {
            XCTAssertEqual(willPresentOptions, [.alert, .badge, .sound])
        }
        XCTAssertEqual(didReceiveOuterCallsCount, 1)
    }

    func testWillPresent_whenCycleHasAnotherPeerReturningEmpty_thenDoesNotLeakCioFallback() {
        let chainedPeer = ChainedNotificationCenterDelegate(previousDelegate: delegate)
        let suppressingPeer = Peer()
        registry.register(chainedPeer)
        registry.register(suppressingPeer)
        var presentationOptions: UNNotificationPresentationOptions?

        delegate.userNotificationCenter(
            UNUserNotificationCenter.current(),
            willPresent: UNNotification.testInstance,
            withCompletionHandler: { presentationOptions = $0 }
        )

        XCTAssertEqual(chainedPeer.willPresentCallsCount, 1)
        XCTAssertEqual(suppressingPeer.willPresentCallsCount, 1)
        XCTAssertEqual(presentationOptions, [])
    }

    func testWillPresent_whenPeerChainsSameNotificationAsynchronously_thenFanOutRunsOnce() {
        let chainedPeer = ChainedNotificationCenterDelegate(previousDelegate: delegate)
        let forwarded = expectation(description: "asynchronous will-present forward returned")
        chainedPeer.forwardsWillPresentAsynchronously = true
        chainedPeer.onAsyncWillPresentForwarded = { forwarded.fulfill() }
        registry.register(chainedPeer)
        var outerCallsCount = 0

        delegate.userNotificationCenter(
            UNUserNotificationCenter.current(),
            willPresent: UNNotification.testInstance,
            withCompletionHandler: { _ in outerCallsCount += 1 }
        )
        wait(for: [forwarded], timeout: 1)

        XCTAssertEqual(chainedPeer.willPresentCallsCount, 1)
        XCTAssertEqual(outerCallsCount, 1)
    }

    func testOpenSettings_whenSeveralPeersImplementSelector_thenCallsEachImplementerOnce() {
        let first = Peer()
        let second = Peer()
        let missingSelectorPeer = Peer()
        missingSelectorPeer.implementsOpenSettings = false
        registry.register(first)
        registry.register(missingSelectorPeer)
        registry.register(second)

        delegate.userNotificationCenter(
            UNUserNotificationCenter.current(),
            openSettingsFor: UNNotification.testInstance
        )

        XCTAssertEqual(first.openSettingsCallsCount, 1)
        XCTAssertEqual(second.openSettingsCallsCount, 1)
        XCTAssertEqual(missingSelectorPeer.openSettingsCallsCount, 0)
    }

    func testOpenSettings_whenPeerChainsSameNotificationAsynchronously_thenFanOutRunsOnce() {
        let chainedPeer = ChainedNotificationCenterDelegate(previousDelegate: delegate)
        let forwarded = expectation(description: "asynchronous open-settings forward returned")
        chainedPeer.forwardsOpenSettingsAsynchronously = true
        chainedPeer.onAsyncOpenSettingsForwarded = { forwarded.fulfill() }
        registry.register(chainedPeer)

        delegate.userNotificationCenter(
            UNUserNotificationCenter.current(),
            openSettingsFor: UNNotification.testInstance
        )
        wait(for: [forwarded], timeout: 1)

        XCTAssertEqual(chainedPeer.openSettingsCallsCount, 1)
    }

    func testOpenSettings_whenPeerChainsNilAsynchronously_thenRunsOncePerForegroundActivation() {
        let chainedPeer = ChainedNotificationCenterDelegate(previousDelegate: delegate)
        chainedPeer.forwardsOpenSettingsAsynchronously = true
        registry.register(chainedPeer)

        for expectedCount in 1 ... 2 {
            let forwarded = expectation(description: "asynchronous nil open-settings forward returned")
            chainedPeer.onAsyncOpenSettingsForwarded = { forwarded.fulfill() }
            delegate.userNotificationCenter(UNUserNotificationCenter.current(), openSettingsFor: nil)
            wait(for: [forwarded], timeout: 1)
            XCTAssertEqual(chainedPeer.openSettingsCallsCount, expectedCount)

            if expectedCount == 1 {
                // A duplicate callback in the same activation is suppressed, while the
                // next real foreground activation starts a new nil delivery.
                delegate.userNotificationCenter(UNUserNotificationCenter.current(), openSettingsFor: nil)
                XCTAssertEqual(chainedPeer.openSettingsCallsCount, expectedCount)
                NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
            }
        }
    }

    private func makeDelegate(showPushAppInForeground: Bool) -> CioNotificationCenterDelegate {
        let config = MessagingPushConfigBuilder()
            .showPushAppInForeground(showPushAppInForeground)
            .build()
        return CioNotificationCenterDelegate(
            messagingPush: MessagingPushInstanceMock(),
            config: { config },
            peerRegistry: registry,
            handlePushResponse: { [weak self] _, _ in
                self?.pushHandlingCallsCount += 1
            }
        )
    }
}
