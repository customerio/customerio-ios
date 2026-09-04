@testable import CioInternalCommon
@testable import CioMessagingInApp
@testable import CioMessagingInAppMocks
import SharedTests
import XCTest

/// Locks the contract that `EngineWeb` reports load failures through its delegate and nothing else.
///
/// `forcedTimeout()` used to dispatch `messageLoadingFailed` itself *and* call `delegate?.error()`.
/// The delegate is `MessageManager`, whose `error()` dispatches that same action — so one 5s timeout
/// delivered the host's `errorWithMessage` callback twice. Every other failure site in `EngineWeb`
/// reports through the delegate alone; the timeout now does too.
class EngineWebTimeoutTests: IntegrationTest {
    private final class EngineWebDelegateSpy: EngineWebDelegate {
        private(set) var errorCallCount = 0

        func bootstrapped() {}
        func tap(name: String, action: String, system: Bool) {}
        func routeChanged(newRoute: String) {}
        func routeError(route: String) {}
        func routeLoaded(route: String) {}
        func sizeChanged(width: CGFloat, height: CGFloat) {}

        func error() {
            errorCallCount += 1
        }
    }

    private var inAppMessageManager: InAppMessageManager!
    private let globalEventListener = InAppEventListenerMock()
    private let delegateSpy = EngineWebDelegateSpy()
    private var engine: EngineWeb!

    override func setUp() {
        super.setUp()

        MessagingInApp.shared.setEventListener(globalEventListener)
        mockCollection.add(mocks: [globalEventListener])

        diGraphShared.override(value: CioThreadUtil(), forType: ThreadUtil.self)
        inAppMessageManager = InAppMessageStoreManager(
            logger: diGraphShared.logger,
            threadUtil: diGraphShared.threadUtil,
            logManager: diGraphShared.logManager,
            gistDelegate: diGraphShared.gistDelegate,
            anonymousMessageManager: diGraphShared.anonymousMessageManager,
            eventBusHandler: diGraphShared.eventBusHandler
        )
        diGraphShared.override(value: inAppMessageManager, forType: InAppMessageManager.self)
    }

    override func tearDown() {
        engine?.cleanEngineWeb()
        engine = nil
        inAppMessageManager = nil
        super.tearDown()
    }

    // `EngineWeb` builds a `WKWebView`, so this has to run on the main actor.
    @MainActor
    func test_forcedTimeout_givenEngineTimesOut_expectDelegateNotifiedOnceAndNoDirectDispatch() async throws {
        // The store drops engine actions while no user is known, so identify first. Without this a
        // stray dispatch from EngineWeb would be swallowed and the assertion below could not see it.
        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: .random))

        let message = Message.random
        engine = EngineWeb(
            configuration: EngineWebConfiguration(
                siteId: .random,
                dataCenter: .random,
                instanceId: message.instanceId,
                endpoint: .random,
                messageId: message.messageId,
                properties: nil
            ),
            state: InAppMessageState(),
            message: message
        )
        engine.delegate = delegateSpy
        // `init` arms the real 5s bootstrap timer. Cancel it before driving the timeout by hand: on
        // a slow runner a test body lasting longer than that would let the real timer fire too, and
        // the extra call would break the once-only assertion for reasons unrelated to the fix.
        engine.cleanEngineWeb()

        engine.forcedTimeout()

        // Flush the store: dispatches are processed in order, so once this one completes any action
        // the timeout might have queued has been processed too.
        await inAppMessageManager.dispatchAsync(action: .setUserIdentifier(user: .random))

        XCTAssertEqual(delegateSpy.errorCallCount, 1)
        // EngineWeb must not reach the store on its own. `MessageManager` owns that dispatch, and
        // doing both is what delivered the host callback twice.
        XCTAssertEqual(globalEventListener.errorWithMessageCallsCount, 0)
    }
}
