import CioInternalCommon
import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

#if canImport(UserNotifications)

/// Snapshot of notification state when `cancel()` delivers best-effort content.
struct NSEPushCancellationDelivery {
    let content: UNNotificationContent
    let handler: (UNNotificationContent) -> Void
    let deliveryId: String
    let requestId: String
    let hasComposed: Bool
}

/// Thread-safe storage for `NSEPushCoordinator` notification state (`contentHandler`, composed content, ids).
final class NSEPushCoordinatorState {
    private static let logTag = "Push"

    private struct State {
        var originalContent: UNNotificationContent?
        var composedRichContent: UNNotificationContent?
        var contentHandler: ((UNNotificationContent) -> Void)?
        var didFinish = false
        var trackedDeliveryId: String?
        var trackedRequestIdentifier: String?
    }

    private let lock = NSLock()
    private var state = State()
    private let logger: Logger

    init(logger: Logger) {
        self.logger = logger
    }

    func notificationAlreadyFinished() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return state.didFinish
    }

    func notificationStateNeedsInitialSetup() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !state.didFinish && state.contentHandler == nil
    }

    func setInitialStateForNotification(
        originalContent: UNNotificationContent,
        contentHandler: @escaping (UNNotificationContent) -> Void,
        deliveryId: String,
        requestIdentifier: String
    ) {
        lock.lock()
        defer { lock.unlock() }
        state.originalContent = originalContent
        state.contentHandler = contentHandler
        state.trackedDeliveryId = deliveryId
        state.trackedRequestIdentifier = requestIdentifier
    }

    func storeComposedRichContent(_ content: UNNotificationContent) {
        lock.lock()
        defer { lock.unlock() }
        state.composedRichContent = content
    }

    func finishIfNeeded(with finalContent: UNNotificationContent) {
        let handler: ((UNNotificationContent) -> Void)?

        lock.lock()
        if state.didFinish {
            handler = nil
        } else {
            state.didFinish = true
            handler = state.contentHandler
            state.contentHandler = nil
        }
        lock.unlock()

        guard let handler else {
            logger.debug(
                "NSE coordinator: skipping contentHandler — already completed (e.g. cancel) (deliveryId: \(trackedIds().deliveryId))",
                Self.logTag
            )
            return
        }

        logger.debug(
            "NSE coordinator: invoking contentHandler — normal completion (deliveryId: \(trackedIds().deliveryId))",
            Self.logTag
        )
        handler(finalContent)
    }

    func takeCancellationDeliveryOrNil() -> NSEPushCancellationDelivery? {
        lock.lock()
        defer { lock.unlock() }

        guard !state.didFinish else {
            return nil
        }

        guard let handler = state.contentHandler else {
            logger.debug(
                "NSE coordinator: cancel — ignored; handle has not stored notification state yet",
                Self.logTag
            )
            return nil
        }

        let content = state.composedRichContent ?? state.originalContent
        guard let content else {
            logger.error(
                "NSE coordinator: cancel — missing original/composed content; cannot deliver (deliveryId: \(state.trackedDeliveryId ?? "unknown"))",
                Self.logTag,
                nil
            )
            return nil
        }

        state.didFinish = true
        state.contentHandler = nil

        let deliveryId = state.trackedDeliveryId ?? "unknown"
        let requestId = state.trackedRequestIdentifier ?? "unknown"
        let hasComposed = state.composedRichContent != nil

        return NSEPushCancellationDelivery(
            content: content,
            handler: handler,
            deliveryId: deliveryId,
            requestId: requestId,
            hasComposed: hasComposed
        )
    }

    private func trackedIds() -> (deliveryId: String, requestId: String) {
        lock.lock()
        defer { lock.unlock() }
        return (state.trackedDeliveryId ?? "unknown", state.trackedRequestIdentifier ?? "unknown")
    }
}

#endif
