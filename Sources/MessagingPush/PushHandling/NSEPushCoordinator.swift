import CioInternalCommon
import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

#if canImport(UserNotifications)

/// Coordinates delivery metric and rich push in parallel for the Notification Service Extension.
/// For production NSE flow, call `prepareNotification(request:withContentHandler:)` synchronously before
/// `Task { await handle(...) }` so `serviceExtensionTimeWillExpire` can `cancel()` even if `handle` has not started yet.
/// Call `handle(request:withContentHandler:autoTrackDelivery:)` once per notification; call `cancel()` on expiry.
final class NSEPushCoordinator: @unchecked Sendable {
    private static let logTag = "Push"

    private let deliveryTracker: RichPushDeliveryTracking
    private let richPushHandler: RichPushRequestHandling
    private let httpClient: HttpClient
    private let logger: Logger
    private let pushLogger: PushNotificationLogger
    private let notificationState: NSEPushCoordinatorState
    private let deliveryContinuationBox = NSEDeliveryContinuationBox()

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
        self.notificationState = NSEPushCoordinatorState(logger: logger)
    }

    /// Stores `contentHandler` and tracking ids **before** `handle` runs (e.g. synchronously in `didReceive`) so `cancel()` can deliver if expiry fires while `handle` is still queued.
    /// Returns `false` when the request has no CIO delivery fields (caller should treat as non-CIO).
    func prepareNotification(
        request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) -> Bool {
        let push = UNNotificationWrapper(notificationRequest: request)
        guard let info = push.cioDelivery else {
            return false
        }
        notificationState.setInitialStateForNotification(
            originalContent: request.content,
            contentHandler: contentHandler,
            deliveryId: info.id,
            requestIdentifier: request.identifier
        )
        return true
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

        guard prepareHandleStateIfNeeded(
            request: request,
            contentHandler: contentHandler,
            deliveryId: info.id,
            requestIdentifier: request.identifier
        ) else {
            return
        }

        if !autoTrackDelivery {
            pushLogger.logPushMetricsAutoTrackingDisabled()
        }

        logger.debug(
            "NSE coordinator: starting parallel delivery metric + rich push (deliveryId: \(info.id), request: \(request.identifier), autoTrackDelivery: \(autoTrackDelivery))",
            Self.logTag
        )

        let finalContent = await loadFinalContent(
            request: request,
            deliveryId: info.id,
            requestIdentifier: request.identifier,
            autoTrackDelivery: autoTrackDelivery
        )
        notificationState.finishIfNeeded(with: finalContent)
    }

    /// Returns `false` when `cancel()` already completed delivery or the coordinator is in a terminal state.
    private func prepareHandleStateIfNeeded(
        request: UNNotificationRequest,
        contentHandler: @escaping (UNNotificationContent) -> Void,
        deliveryId: String,
        requestIdentifier: String
    ) -> Bool {
        if notificationState.notificationAlreadyFinished() {
            return false
        }

        if notificationState.notificationStateNeedsInitialSetup() {
            notificationState.setInitialStateForNotification(
                originalContent: request.content,
                contentHandler: contentHandler,
                deliveryId: deliveryId,
                requestIdentifier: requestIdentifier
            )
        }

        if notificationState.notificationAlreadyFinished() {
            return false
        }

        return true
    }

    private func loadFinalContent(
        request: UNNotificationRequest,
        deliveryId: String,
        requestIdentifier: String,
        autoTrackDelivery: Bool
    ) async -> UNNotificationContent {
        if autoTrackDelivery {
            async let deliveryTask: Void = trackDeliveredMetric(request: request)
            async let richPushTask: UNNotificationContent = processRichPush(request: request)
            let rich = await richPushTask
            notificationState.storeComposedRichContent(rich)
            logger.debug(
                "NSE coordinator: rich push step finished (deliveryId: \(deliveryId), request: \(requestIdentifier))",
                Self.logTag
            )
            await deliveryTask
            logger.debug(
                "NSE coordinator: delivery metric step finished (deliveryId: \(deliveryId), request: \(requestIdentifier))",
                Self.logTag
            )
            return rich
        }

        let content = await processRichPush(request: request)
        notificationState.storeComposedRichContent(content)
        logger.debug(
            "NSE coordinator: rich push step finished (deliveryId: \(deliveryId), request: \(requestIdentifier))",
            Self.logTag
        )
        return content
    }

    /// Called from `serviceExtensionTimeWillExpire()`: stop work, unblock delivery wait, deliver best-effort content once.
    func cancel() {
        guard let contentToDeliver = notificationState.takeCancellationDeliveryOrNil() else {
            // Not prepared yet, already finished, or duplicate cancel — do not stop work or invalidate the HTTP
            // client when `handle` has not acquired resources (production should call `prepareNotification` first).
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

            let continuationBox = deliveryContinuationBox
            deliveryTracker.trackMetric(request: request, event: .delivered) { [continuationBox] _ in
                _ = continuationBox.resumeIfNeeded()
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
}

#endif
