import CioInternalCommon
import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/**
 Coordinates both metrics tracking and rich push processing in NSE context.
 Ensures contentHandler is called exactly once when both operations complete or timeout occurs.
 */
#if canImport(UserNotifications)
class NSEOperationCoordinator {
    // MARK: - Private Properties

    private let push: UNNotificationWrapper
    private let contentHandler: (UNNotificationContent) -> Void
    private let richPushHandler: RichPushRequestHandler
    private let pushDeliveryTracker: RichPushDeliveryTracker
    private let logger: Logger

    private let state: OperationState

    // MARK: - Initialization

    init(
        push: UNNotificationWrapper,
        contentHandler: @escaping (UNNotificationContent) -> Void,
        richPushHandler: RichPushRequestHandler,
        pushDeliveryTracker: RichPushDeliveryTracker,
        logger: Logger
    ) {
        self.push = push
        self.contentHandler = contentHandler
        self.richPushHandler = richPushHandler
        self.pushDeliveryTracker = pushDeliveryTracker
        self.logger = logger

        // Initialize with original notification content
        let originalContent = push.notificationContent
        self.state = OperationState(originalContent: originalContent)
    }

    // MARK: - Public Interface

    func start() {
        logger.debug("Starting coordinated NSE operations for deliveryId: \(String(describing: push.cioDelivery?.id))")

        // Start both operations concurrently
        startMetricsTracking()
        startRichPushProcessing()
    }

    func handleTimeWillExpire() {
        logger.info("NSE time will expire. Stopping all operations and using current content.")

        // Cancel any pending operations
        richPushHandler.stopAll()

        // Force completion with whatever content we have
        let finalContent = state.forceComplete()
        callContentHandler(with: finalContent, reason: "timeWillExpire")
    }

    /// Current notification content. Useful for testing thread safety.
    var currentContent: UNNotificationContent {
        state.currentContent
    }

    // MARK: - Private Methods

    private func startMetricsTracking() {
        // Note: push.cioDelivery is guaranteed to exist because coordinator is only created
        // when the extension has already verified cioDelivery exists
        let deliveryInfo = push.cioDelivery!

        logger.debug("Starting metrics tracking for deliveryId: \(deliveryInfo.id)")

        pushDeliveryTracker.trackMetric(token: deliveryInfo.token, event: .delivered, deliveryId: deliveryInfo.id, timestamp: nil) { [weak self] result in
            self?.handleMetricsCompletion(result: result)
        }
    }

    private func startRichPushProcessing() {
        logger.debug("Starting rich push processing")

        richPushHandler.startRequest(push: push) { [weak self] modifiedPush in
            self?.handleRichPushCompletion(modifiedPush: modifiedPush)
        }
    }

    private func handleMetricsCompletion(result: Result<Void, HttpRequestError>) {
        switch result {
        case .success:
            logger.debug("Metrics tracking completed successfully for deliveryId: \(String(describing: push.cioDelivery?.id))")
        case .failure(let error):
            logger.error("Metrics tracking failed for deliveryId: \(String(describing: push.cioDelivery?.id)): \(error)")
        }

        if let finalContent = state.markMetricsComplete() {
            callContentHandler(with: finalContent, reason: "bothOperationsComplete")
        }
    }

    private func handleRichPushCompletion(modifiedPush: PushNotification) {
        logger.debug("Rich push processing completed for deliveryId: \(String(describing: push.cioDelivery?.id))")

        let content = (modifiedPush as? UNNotificationWrapper)?.notificationContent ?? state.currentContent

        if let finalContent = state.markRichPushComplete(with: content) {
            callContentHandler(with: finalContent, reason: "bothOperationsComplete")
        }
    }

    private func callContentHandler(with content: UNNotificationContent, reason: String) {
        logger.info("NSE operations complete (\(reason)). Calling content handler.")

        contentHandler(content)
    }
}

// MARK: - Thread-Safe State Management

private struct OperationData {
    var metricsCompleted = false
    var richPushCompleted = false
    var handlerCalled = false
    var currentContent: UNNotificationContent

    init(originalContent: UNNotificationContent) {
        self.currentContent = originalContent
    }
}

private class OperationState {
    private var state: Synchronized<OperationData>

    init(originalContent: UNNotificationContent) {
        self.state = Synchronized(OperationData(originalContent: originalContent))
    }

    /// Marks metrics as complete and returns final content if both operations are done
    func markMetricsComplete() -> UNNotificationContent? {
        state.value { data in
            data.metricsCompleted = true

            // Check if both operations complete and handler not called yet
            if data.metricsCompleted, data.richPushCompleted, !data.handlerCalled {
                data.handlerCalled = true
                return data.currentContent
            }
            return nil
        }
    }

    /// Marks rich push as complete and returns final content if both operations are done
    func markRichPushComplete(with content: UNNotificationContent) -> UNNotificationContent? {
        state.value { data in
            data.currentContent = content
            data.richPushCompleted = true

            // Check if both operations complete and handler not called yet
            if data.metricsCompleted, data.richPushCompleted, !data.handlerCalled {
                data.handlerCalled = true
                return data.currentContent
            }
            return nil
        }
    }

    /// Returns current content without modifying state
    var currentContent: UNNotificationContent {
        state.value.currentContent
    }

    /// Forces completion and returns current content (for timeout scenarios)
    func forceComplete() -> UNNotificationContent {
        state.value { data in
            data.handlerCalled = true
            return data.currentContent
        }
    }
}
#endif
