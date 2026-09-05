import CioDataPipelines
import CioInternalCommon
import CioLiveActivities
import CioLiveActivities_Templates
import CioLocation
import CioLocationGeofence
import CioMessagingInApp
import CioMessagingPush
import CioMessagingPushAPN
import os
import UIKit

@main
class AppDelegateWithCioIntegration: CioAppDelegateWrapper<AppDelegate> {}

class AppDelegate: UIResponder, UIApplicationDelegate {
    var storage = DIGraphShared.shared.storage
    var deepLinkHandler = DIGraphShared.shared.deepLinksHandlerUtil
    private let inboxEventListener = SampleInboxEventListener()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Field-drive diagnostics sink, installed before anything else runs.
        //
        // A cold background wake — the geofence case we care most about — reaches SDK code within
        // milliseconds of process start. Anything installed after SDK initialization, or from a
        // scene delegate, misses the wake it was meant to observe.
        DiagnosticLog.shared.start()

        // Geofence cold-wake delivery: iOS can launch the app into the background for a transition,
        // so region monitoring is wired here rather than relying on CustomerIO.initialize. Matches
        // the React Native and Flutter samples; safe alongside normal init.
        GeofenceModule.bootstrapForBackgroundDelivery(launchOptions: launchOptions)

        // Override point for customization after application launch.
        initializeCioAndInAppListeners()

        /*
         Registers the `AppDelegate` class to handle when a push notification gets clicked.
         This line of code is optional and only required if you have custom code that needs to run when a push notification gets clicked on.
         Push notifications sent by Customer.io will be handled by the Customer.io SDK automatically, unless you disabled that feature.
         Therefore, this line of code is not required if you only want to handle push notifications sent by Customer.io.
         */
//        UNUserNotificationCenter.current().delegate = self

        return true
    }

    func initializeCioAndInAppListeners() {
        // Set default setting if those don't exist
        DIGraphShared.shared.settingsService.setDefaultSettings()

        // Initialize CustomerIO SDK
        guard let settings = storage.settings else {
            assertionFailure("Settings should not be nil")
            return
        }

        let config = SDKConfigBuilder(cdpApiKey: settings.dataPipelines.cdpApiKey)
            .region(settings.dataPipelines.region.toCIORegion())
            .autoTrackDeviceAttributes(settings.dataPipelines.autoTrackDeviceAttributes)
            .trackApplicationLifecycleEvents(settings.dataPipelines.trackApplicationLifecycleEvents)
            .screenViewUse(screenView: settings.dataPipelines.screenViewUse.toCIOScreenViewUse())
            // Forced to `.debug` rather than taking the stored setting. The SDK filters by level
            // *before* the dispatcher runs, and `CustomerIO.initialize` re-applies the configured
            // level over whatever the sink set at install time — so a stored level of ERROR would
            // produce an empty file after a three-hour drive. Diagnostics win over the setting;
            // the Location Test screen says so on screen.
            .logLevel(.debug)
            .migrationSiteId(settings.dataPipelines.siteId)
            .deepLinkCallback { [deepLinkHandler] url in deepLinkHandler.handleCustomerIODestination(url) }

        if settings.dataPipelines.autoTrackUIKitScreenViews {
            config.autoTrackUIKitScreenViews()
        }
        if case let apiHost = settings.internalSettings.apiHost, !apiHost.isEmpty {
            config.apiHost(apiHost)
        }
        if case let cdnHost = settings.internalSettings.cdnHost, !cdnHost.isEmpty {
            config.cdnHost(cdnHost)
        }
        if settings.internalSettings.testMode {
            config.flushAt(1)
        }
        let locationMode = settings.location?.trackingMode.toCIOMode() ?? .manual
        config.addModule(LocationModule(config: LocationConfig(mode: locationMode)))
        config.addModule(GeofenceModule())
        addLiveActivitiesModule(to: config)
        CustomerIO.initialize(withConfig: config.build())

        // Initialize messaging features after initializing Customer.io SDK
        MessagingPushAPN.initialize(
            withConfig: MessagingPushConfigBuilder()
                .autoFetchDeviceToken(settings.messaging.autoFetchDeviceToken)
                .autoTrackPushEvents(settings.messaging.autoTrackPushEvents)
                .showPushAppInForeground(settings.messaging.showPushAppInForeground)
                .appGroupId("group.io.customer.ios-sample.apn-spm.APN-UIKit.cio")
                .build()
        )
        MessagingInApp
            .initialize(withConfig: MessagingInAppConfigBuilder(
                siteId: settings.inApp.siteId,
                region: settings.inApp.region.toCIORegion()
            ).build())
            .setEventListener(self)

        // Visual Notification Inbox action listener. Observational here (logs each callback and
        // returns `false` so the SDK runs its default action handling). A host that wants to
        // intercept an action returns `true` from `messageActionTaken`.
        MessagingInApp.shared.setInboxEventListener(inboxEventListener)
    }

    // Register Live Activities as an SDK-managed module. It initializes during
    // CustomerIO.initialize(withConfig:) and is reached via `CustomerIO.liveActivities`.
    // `DeliveryActivityAttributes` is defined in the widget extension folder and shared with
    // this target; the SDK matches it by type name.
    private func addLiveActivitiesModule(to config: SDKConfigBuilder) {
        guard #available(iOS 16.2, *) else { return }
        config.addModule(LiveActivitiesModule(
            config:
            LiveActivityConfigBuilder()
                // Built-in templates carry their own identifier (CIOActivityTemplate) — no id needed.
                .register(CIOSegmentsAttributes.self)
                .register(CIOCountdownTimerAttributes.self)
                // A custom (app-owned) type: pass the identifier the backend expects.
                .register(DeliveryActivityAttributes.self, identifier: DeliveryActivityAttributes.identifier)
                .build()
        ))
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }
}

/*
 The lines of code below are optional and only required if you:
 - want fine-grained control over whether notifications are shown in the foreground
 - have custom code that needs to run when a push notification gets clicked on.
 Push notifications sent by Customer.io will be handled by the Customer.io SDK automatically, unless you disabled that feature.
 Therefore, lines of code below are not required if you only want to handle push notifications sent by Customer.io.
 */
// extension AppDelegate: UNUserNotificationCenterDelegate {
//    // Function called when a push notification is clicked or swiped away.
//    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
//        // Track custom event with Customer.io.
//        // NOT required for basic PN tap tracking - that is done automatically with `CioAppDelegateWrapper`.
//        CustomerIO.shared.track(
//            name: "custom push-clicked event",
//            properties: ["push": response.notification.request.content.userInfo]
//        )
//
//        completionHandler()
//    }
//
//    // To test sending of local notifications, display the push while app in foreground. So when you press the button to display local push in the app, you are able to see it and click on it.
//    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
//        completionHandler([.banner, .badge, .sound])
//    }
// }

// In-app event listeners to handle user's response to in-app messages.
// Registering event listeners is requiredf
extension AppDelegate: InAppEventListener {
    // Message is sent and shown to the user
    nonisolated func messageShown(message: InAppMessage) {
        CustomerIO.shared.track(
            name: "inapp shown",
            properties: ["delivery-id": message.deliveryId ?? "(none)", "message-id": message.messageId]
        )
    }

    // User taps X (close) button and in-app message is dismissed
    nonisolated func messageDismissed(message: InAppMessage) {
        CustomerIO.shared.track(
            name: "inapp dismissed",
            properties: ["delivery-id": message.deliveryId ?? "(none)", "message-id": message.messageId]
        )
    }

    // In-app message produces an error - preventing message from appearing to the user.
    // Still a requirement of the protocol; the SDK calls the overload below, which carries the reason.
    nonisolated func errorWithMessage(message: InAppMessage) {
        CustomerIO.shared.track(
            name: "inapp error",
            properties: ["delivery-id": message.deliveryId ?? "(none)", "message-id": message.messageId]
        )
    }

    nonisolated func errorWithMessage(message: InAppMessage, error: InAppMessageError) {
        // `detail` is deliberately logged but not tracked: it is diagnostic text, partly supplied
        // by the renderer, and not something to forward verbatim to analytics.
        print("in-app message failed: \(error.reason.rawValue) — \(error.detail ?? "(no detail)")")
        CustomerIO.shared.track(
            name: "inapp error",
            properties: [
                "delivery-id": message.deliveryId ?? "(none)",
                "message-id": message.messageId,
                "error-reason": error.reason.rawValue,
                "error-code": error.code.map(String.init) ?? "(none)"
            ]
        )
    }

    // User perform an action on in-app message
    nonisolated func messageActionTaken(message: InAppMessage, actionValue: String, actionName: String) {
        if actionName == "remove" || actionName == "test" {
            MessagingInApp.shared.dismissMessage()
        }
        CustomerIO.shared.track(name: "inapp action", properties: [
            "delivery-id": message.deliveryId ?? "(none)",
            "message-id": message.messageId,
            "action-value": actionValue,
            "action-name": actionName
        ])
    }
}

/// Sample listener for Visual Notification Inbox events. Observational: it logs each callback and
/// returns `false` from `messageActionTaken` so the SDK still applies its default action
/// handling (e.g. opening an http(s) url). Return `true` instead to fully handle the action and
/// suppress the SDK's default behavior.
class SampleInboxEventListener: InboxEventListener {
    private static let log = OSLog(subsystem: "io.customer.ios-sample.apn-uikit", category: "CIO-Inbox")

    func messageActionTaken(message: InboxMessage, actionName: String, actionValue: String) -> Bool {
        os_log(
            "[CIO-Inbox] sample listener: actionTaken queueId=%{public}@ name=%{public}@ value=%{public}@",
            log: Self.log,
            type: .info,
            message.queueId,
            actionName,
            actionValue
        )
        return false
    }

    func messageShown(message: InboxMessage) {
        os_log("[CIO-Inbox] sample listener: shown queueId=%{public}@", log: Self.log, type: .info, message.queueId)
    }

    func messageOpened(message: InboxMessage) {
        os_log("[CIO-Inbox] sample listener: opened queueId=%{public}@", log: Self.log, type: .info, message.queueId)
    }

    func messageDismissed(message: InboxMessage) {
        os_log("[CIO-Inbox] sample listener: dismissed queueId=%{public}@", log: Self.log, type: .info, message.queueId)
    }
}
