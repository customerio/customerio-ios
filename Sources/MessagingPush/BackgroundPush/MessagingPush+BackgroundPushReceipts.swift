@_spi(Internal) import CioInternalCommon
import Foundation

extension MessagingPush {
    /// The one receipt sender, created on first use. A host can handle a push before calling `initialize`,
    /// so that push's receipt is saved then and left for `initialize` to send or remove.
    @available(iOSApplicationExtension, unavailable)
    static func backgroundPushReceiptSenderCreatingIfNeeded() -> BackgroundPushReceiptSender {
        backgroundPushReceiptSender.mutating { existing in
            if let existing { return existing }
            let graph = DIGraphShared.shared
            let taskRunner: BackgroundTaskRunner = graph.getOverriddenInstance() ?? UIKitBackgroundTaskRunner(name: "io.customer.background-push-receipt")
            let created = BackgroundPushReceiptSender(
                store: CioAppGroupPendingPushDeliveryStore(privateFileURL: BackgroundPushReceiptSender.defaultFileURL(), logger: graph.logger),
                httpClient: graph.backgroundDeliveryHttpClient,
                taskRunner: taskRunner,
                logger: graph.logger
            )
            existing = created
            return created
        }
    }

    /// Starts sending saved receipts, or removes them when `autoTrackPushEvents` is off.
    @available(iOSApplicationExtension, unavailable)
    static func startBackgroundPushReceipts(config: MessagingPushConfigOptions) {
        let receiptSender = backgroundPushReceiptSenderCreatingIfNeeded()
        receiptSender.observeContextReadiness(DIGraphShared.shared.eventBusHandler)
        receiptSender.start(autoTrackPushEvents: config.autoTrackPushEvents)
    }
}
