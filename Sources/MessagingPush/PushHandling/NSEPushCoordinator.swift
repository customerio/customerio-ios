import CioInternalCommon
import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

#if canImport(UserNotifications)

/// Coordinates delivery metric and rich push in parallel for the Notification Service Extension.
///
/// **Persistence is best-effort only:** missing App Groups, wrong `group.{bundleId}.cio`, full disk, or I/O errors never
/// block the delivery-metric HTTP request or rich-push image download—those paths always run when auto-tracking / image
/// URLs apply. The app group file is only a backup queue for the main app to flush if the NSE cannot complete cleanly.
///
/// Persists a pending “delivered” metric to the app group **before** the delivery HTTP request starts (same process
/// ordering as the network attempt). Removes that entry **after** the HTTP layer reports success, so the main app does
/// not re-flush a metric the server already received—even if `serviceExtensionTimeWillExpire` ran first (in-flight
/// requests may still complete). Entries remain if the request fails or the extension is killed before completion.
///
/// For production NSE flow, call `prepareNotification(request:withContentHandler:)` synchronously before
/// `Task { await handle(...) }` so `serviceExtensionTimeWillExpire` can `cancel()` even if `handle` has not started yet.
/// Call `handle(request:withContentHandler:autoTrackDelivery:)` once per notification; call `cancel()` on expiry.
final class NSEPushCoordinator: @unchecked Sendable {
    private static let logTag = "Push"

    private let deliveryTracker: RichPushDeliveryTracking
    private let richPushHandler: RichPushRequestHandling
    private let httpClient: HttpClient
    private let pendingPushDeliveryStore: PendingPushDeliveryStore
    private let logger: Logger
    private let pushLogger: PushNotificationLogger
    private let notificationState: NSEPushCoordinatorState
    private let deliveryContinuationBox = NSEDeliveryContinuationBox()

    init(
        deliveryTracker: RichPushDeliveryTracking,
        pushLogger: PushNotificationLogger,
        logger: Logger,
        richPushHandler: RichPushRequestHandling,
        httpClient: HttpClient,
        pendingPushDeliveryStore: PendingPushDeliveryStore
    ) {
        self.deliveryTracker = deliveryTracker
        self.pushLogger = pushLogger
        self.logger = logger
        self.richPushHandler = richPushHandler
        self.httpClient = httpClient
        self.pendingPushDeliveryStore = pendingPushDeliveryStore
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

        let pendingMetricIdToRemoveOnSuccess = persistPendingDeliveryMetricForNSEIfNeeded(
            deliveryId: info.id,
            deviceToken: info.token,
            autoTrackDelivery: autoTrackDelivery
        )

        logger.debug(
            "NSE coordinator: starting parallel delivery metric + rich push (deliveryId: \(info.id), request: \(request.identifier), autoTrackDelivery: \(autoTrackDelivery))",
            Self.logTag
        )

        let finalContent = await loadFinalContent(
            request: request,
            deliveryId: info.id,
            requestIdentifier: request.identifier,
            autoTrackDelivery: autoTrackDelivery,
            pendingMetricIdToRemoveOnSuccess: pendingMetricIdToRemoveOnSuccess
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
        autoTrackDelivery: Bool,
        pendingMetricIdToRemoveOnSuccess: UUID?
    ) async -> UNNotificationContent {
        if autoTrackDelivery {
            async let deliveryTask: Void = trackDeliveredMetric(
                request: request,
                pendingMetricIdToRemoveOnSuccess: pendingMetricIdToRemoveOnSuccess
            )
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

    // MARK: - Pending delivery file (app group)

    /// Returns the metric id to remove after a successful delivery HTTP response, or `nil` if auto-tracking is off or
    /// local persistence did not queue a row (delivery HTTP still runs in all cases).
    private func persistPendingDeliveryMetricForNSEIfNeeded(
        deliveryId: String,
        deviceToken: String,
        autoTrackDelivery: Bool
    ) -> UUID? {
        guard autoTrackDelivery else { return nil }

        let metric = PendingPushDeliveryMetric(
            deliveryId: deliveryId,
            deviceToken: deviceToken,
            event: .delivered,
            timestamp: Date()
        )
        if pendingPushDeliveryStore.append(metric) {
            return metric.id
        }

        // App group container missing, disk full, permission, etc.—never block or downgrade the network path.
        logger.debug(
            "Pending push delivery store: could not persist pending metric (deliveryId: \(deliveryId)); delivery metric HTTP and rich push are unchanged.",
            Self.logTag
        )
        return nil
    }

    // MARK: - Parallel branches

    private func trackDeliveredMetric(
        request: UNNotificationRequest,
        pendingMetricIdToRemoveOnSuccess: UUID?
    ) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            deliveryContinuationBox.install(continuation)

            let continuationBox = deliveryContinuationBox
            deliveryTracker.trackMetric(request: request, event: .delivered) { [weak self] result in
                defer {
                    _ = continuationBox.resumeIfNeeded()
                }
                guard let self else { return }
                guard case .success = result, let id = pendingMetricIdToRemoveOnSuccess else { return }
                // Always drop the pending file row when HTTP reports success so Data Pipeline startup does not
                // duplicate a metric the backend already accepted (even if NSE expiry ran while the task finished).
                if !self.pendingPushDeliveryStore.remove(id: id) {
                    self.logger.debug(
                        "NSE coordinator: pending metric id=\(id) not removed after delivery success (deliveryId may still flush from app group)",
                        Self.logTag
                    )
                }
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
