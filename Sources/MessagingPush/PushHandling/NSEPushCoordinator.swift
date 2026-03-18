import CioInternalCommon
import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

#if canImport(UserNotifications)

// MARK: - Delivery continuation (resume from metric callback or NSE cancel)

private enum NSEDeliveryContinuationState: Sendable {
    case idle
    case waiting
    case resumed
    case cancelled
}

/// Bridges callback-based delivery tracking into async/await and allows `cancel()` to resume early.
private final class DeliveryContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var state: NSEDeliveryContinuationState = .idle
    private var continuation: CheckedContinuation<Void, Never>?

    func install(_ continuation: CheckedContinuation<Void, Never>) {
        lock.lock()
        defer { lock.unlock() }

        switch state {
        case .idle:
            self.continuation = continuation
            state = .waiting

        case .cancelled, .resumed:
            continuation.resume()

        case .waiting:
            assertionFailure("DeliveryContinuationBox.install called while already waiting")
            continuation.resume()
        }
    }

    @discardableResult
    func resumeIfNeeded(markCancelled: Bool = false) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        switch state {
        case .waiting:
            let continuation = self.continuation
            self.continuation = nil
            state = markCancelled ? .cancelled : .resumed
            continuation?.resume()
            return true

        case .idle:
            state = markCancelled ? .cancelled : .resumed
            return false

        case .resumed, .cancelled:
            return false
        }
    }
}

/// Coordinates delivery metric and rich push in parallel for the Notification Service Extension.
/// Call `handle(request:withContentHandler:autoTrackDelivery:)` once per notification; call `cancel()` on expiry.
final class NSEPushCoordinator: @unchecked Sendable {
    private static let logTag = "Push"

    private struct State {
        var originalContent: UNNotificationContent?
        var composedRichContent: UNNotificationContent?
        var contentHandler: ((UNNotificationContent) -> Void)?
        var didFinish = false
        var trackedDeliveryId: String?
        var trackedRequestIdentifier: String?
    }

    private let deliveryTracker: RichPushDeliveryTracking
    private let richPushHandler: RichPushRequestHandling
    private let httpClient: HttpClient
    private let logger: Logger
    private let pushLogger: PushNotificationLogger
    private let deliveryContinuationBox = DeliveryContinuationBox()

    private let lock = NSLock()
    private var state = State()

    init(
        deliveryTracker: RichPushDeliveryTracking,
        pushLogger: PushNotificationLogger,
        logger: Logger,
        richPushHandler: RichPushRequestHandling,
        httpClient: HttpClient
    ) {
        self.deliveryTracker = deliveryTracker
        self.pushLogger = pushLogger
        self.logger = logger
        self.richPushHandler = richPushHandler
        self.httpClient = httpClient
    }

    /// Owns the NSE flow for one notification request: optional delivered metric, rich push, parallel run, then `contentHandler` once.
    func handle(
        request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void,
        autoTrackDelivery: Bool
    ) async {
        let push = UNNotificationWrapper(notificationRequest: request)
        guard let info = push.cioDelivery else {
            logger.debug(
                "NSE coordinator: no CIO delivery in payload; passing through content (request: \(request.identifier))",
                Self.logTag
            )
            contentHandler(request.content)
            return
        }

        setInitialStateForNotification(
            originalContent: request.content,
            contentHandler: contentHandler,
            deliveryId: info.id,
            requestIdentifier: request.identifier
        )

        if !autoTrackDelivery {
            pushLogger.logPushMetricsAutoTrackingDisabled()
        }

        logger.debug(
            "NSE coordinator: starting parallel delivery metric + rich push (deliveryId: \(info.id), request: \(request.identifier), autoTrackDelivery: \(autoTrackDelivery))",
            Self.logTag
        )

        let finalContent: UNNotificationContent
        if autoTrackDelivery {
            async let deliveryTask: Void = trackDeliveredMetric(request: request)
            async let richPushTask: UNNotificationContent = processRichPush(request: request)
            let rich = await richPushTask
            storeComposedRichContent(rich)
            logger.debug(
                "NSE coordinator: rich push step finished (deliveryId: \(info.id), request: \(request.identifier))",
                Self.logTag
            )
            await deliveryTask
            logger.debug(
                "NSE coordinator: delivery metric step finished (deliveryId: \(info.id), request: \(request.identifier))",
                Self.logTag
            )
            finalContent = rich
        } else {
            finalContent = await processRichPush(request: request)
            storeComposedRichContent(finalContent)
            logger.debug(
                "NSE coordinator: rich push step finished (deliveryId: \(info.id), request: \(request.identifier))",
                Self.logTag
            )
        }

        finishIfNeeded(with: finalContent)
    }

    /// Called from `serviceExtensionTimeWillExpire()`: stop work, unblock delivery wait, deliver best-effort content once.
    func cancel() {
        guard let contentToDeliver = takeCancellationDeliveryOrNil() else {
            // No in-flight notification state yet, already finished, or duplicate cancel — do not stop work or
            // invalidate the HTTP client (still needed if `handle` has not run).
            return
        }

        richPushHandler.stopAll()
        // Single invalidation for this coordinator's client: `RichPushRequest.cancel()` must not also call
        // `httpClient.cancel`, or URLSession would be invalidated twice (undefined behavior per Apple docs).
        httpClient.cancel(finishTasks: false)
        _ = deliveryContinuationBox.resumeIfNeeded(markCancelled: true)

        logger.debug(
            "NSE coordinator: cancel — delivering best-effort content (deliveryId: \(contentToDeliver.deliveryId), request: \(contentToDeliver.requestId), hasComposedRichContent: \(contentToDeliver.hasComposed))",
            Self.logTag
        )
        contentToDeliver.handler(contentToDeliver.content)
    }

    // MARK: - Parallel branches

    private func trackDeliveredMetric(request: UNNotificationRequest) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            deliveryContinuationBox.install(continuation)

            deliveryTracker.trackMetric(request: request, event: .delivered) { _ in
                _ = self.deliveryContinuationBox.resumeIfNeeded()
            }
        }
    }

    private func processRichPush(request: UNNotificationRequest) async -> UNNotificationContent {
        await withCheckedContinuation { continuation in
            richPushHandler.start(request: request) { [weak self] result in
                guard let self else {
                    continuation.resume(returning: request.content)
                    return
                }

                let content: UNNotificationContent
                switch result {
                case .success(let richContent):
                    self.logger.debug("Rich push content composed successfully.", Self.logTag)
                    content = richContent
                case .failure(let error):
                    self.logger.error("Rich push processing failed.", Self.logTag, error)
                    content = request.content
                }

                continuation.resume(returning: content)
            }
        }
    }

    // MARK: - State

    /// Synchronous: Swift 6 disallows `NSLock` in `async` functions; keep all locking here or in other non-async methods.
    private func setInitialStateForNotification(
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

    private func storeComposedRichContent(_ content: UNNotificationContent) {
        lock.lock()
        defer { lock.unlock() }
        state.composedRichContent = content
    }

    private func finishIfNeeded(with finalContent: UNNotificationContent) {
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

    private struct CancellationDelivery {
        let content: UNNotificationContent
        let handler: (UNNotificationContent) -> Void
        let deliveryId: String
        let requestId: String
        let hasComposed: Bool
    }

    private func takeCancellationDeliveryOrNil() -> CancellationDelivery? {
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

        return CancellationDelivery(
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
