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
    @available(iOSApplicationExtension, unavailable)
    static func initializeBackgroundPushSupport(config: MessagingPushConfigOptions) {
        let graph = DIGraphShared.shared
        let taskRunner: BackgroundTaskRunner = graph.getOverriddenInstance() ?? UIKitBackgroundTaskRunner(name: "io.customer.background-push-receipt")
        let receiptSender: BackgroundPushReceiptSender = graph.getOverriddenInstance() ?? BackgroundPushReceiptSender(
            store: CioAppGroupPendingPushDeliveryStore(privateFileURL: BackgroundPushReceiptSender.defaultFileURL(), logger: graph.logger),
            httpClient: graph.backgroundDeliveryHttpClient,
            taskRunner: taskRunner,
            logger: graph.logger
        )
        Self.backgroundPushReceiptSender = receiptSender
        receiptSender.observeContextReadiness(graph.eventBusHandler)
        receiptSender.scheduleDrain()
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
