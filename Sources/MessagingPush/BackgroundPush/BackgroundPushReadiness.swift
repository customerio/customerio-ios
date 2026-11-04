@_spi(Internal) import CioInternalCommon
import Foundation

/// Whether this app can run background push callbacks: the host enabled `backgroundPushEnabled`
/// and its Info.plist `UIBackgroundModes` lists `remote-notification`.
enum BackgroundPushReadiness {
    static let requiredBackgroundMode = "remote-notification"

    /// - Parameter backgroundModes: the raw `UIBackgroundModes` Info.plist value, which may be missing or malformed.
    static func isReady(enabled: Bool, backgroundModes: Any?) -> Bool {
        guard enabled, let modes = backgroundModes as? [String] else { return false }
        return modes.contains(requiredBackgroundMode)
    }
}

extension MessagingPush {
    /// The one receipt sender, created on first use. A host can handle a push before calling `initialize`,
    /// so that push's receipt is saved then and sent once the SDK can reach Customer.io.
    @available(iOSApplicationExtension, unavailable)
    static func backgroundPushReceiptSenderCreatingIfNeeded() -> BackgroundPushReceiptSender {
        backgroundPushReceiptSenderStorage.mutating { existing in
            if let existing { return existing }
            let graph = DIGraphShared.shared
            let taskRunner: BackgroundTaskRunner = graph.getOverriddenInstance() ?? UIKitBackgroundTaskRunner(name: "io.customer.background-push-receipt")
            let created: BackgroundPushReceiptSender = graph.getOverriddenInstance() ?? BackgroundPushReceiptSender(
                store: CioAppGroupPendingPushDeliveryStore(privateFileURL: BackgroundPushReceiptSender.defaultFileURL(), logger: graph.logger),
                httpClient: graph.backgroundDeliveryHttpClient,
                taskRunner: taskRunner,
                logger: graph.logger
            )
            existing = created
            return created
        }
    }

    @available(iOSApplicationExtension, unavailable)
    static func initializeBackgroundPushSupport(config: MessagingPushConfigOptions) {
        let graph = DIGraphShared.shared
        let receiptSender = backgroundPushReceiptSenderCreatingIfNeeded()
        receiptSender.observeContextReadiness(graph.eventBusHandler)
        receiptSender.start(autoTrackPushEvents: config.autoTrackPushEvents)
        let backgroundPushReady = BackgroundPushReadiness.isReady(
            enabled: config.backgroundPushEnabled,
            backgroundModes: Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes")
        )
        if config.backgroundPushEnabled, !backgroundPushReady {
            DIGraphShared.shared.logger.error(
                "Background push is enabled, but Info.plist UIBackgroundModes lacks remote-notification. This device will be registered as unable to receive background pushes."
            )
        }
        DIGraphShared.shared.eventBusHandler.postEvent(BackgroundPushReadinessChangedEvent(ready: backgroundPushReady))
    }
}
