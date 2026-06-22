import CioDataPipelines
import CioInternalCommon
import CioLocation
import CioLocationGeofence
import CioMessagingInApp
import CioMessagingPush
import CioMessagingPushAPN
import UIKit
import UserNotifications // testing-only — for GeofenceTestNotifier

@main
class AppDelegateWithCioIntegration: CioAppDelegateWrapper<AppDelegate> {}

class AppDelegate: UIResponder, UIApplicationDelegate {
    var storage = DIGraphShared.shared.storage
    var deepLinkHandler = DIGraphShared.shared.deepLinksHandlerUtil

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
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
        // === TESTING-ONLY === geofence-testing branch only — must not merge.
        // Installs BEFORE CustomerIO.initialize so the dispatcher is wired
        // into the singleton logger before SDK init starts emitting.
        SdkFileLogger.install()
        // === END TESTING-ONLY ===

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
            .logLevel(settings.dataPipelines.logLevel.toCIOLogLevel())
            .migrationSiteId(settings.dataPipelines.siteId)

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
        let locationMode = settings.location?.trackingMode.toCIOMode() ?? .onAppStart
        config.addModule(LocationModule(config: LocationConfig(mode: locationMode)))
        config.addModule(GeofenceModule())
        CustomerIO.initialize(withConfig: config.build())

        // === TESTING-ONLY === geofence-testing branch only — must not merge.
        // Shows a local UNNotification on every geofence transition the SDK accepts.
        GeofenceTestNotifier.install()
        // === END TESTING-ONLY ===

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
    }

    // Handle Universal Link deep link from the Customer.io SDK. This function will get called if a push notification
    // gets clicked that has a Universal Link deep link attached and the app is in the foreground. Otherwise, another function
    // in your app may get called depending on what technology you use (Scenes, UIKit, Swift UI).
    //
    // Learn more: https://customer.io/docs/sdk/ios/push/#universal-links-deep-links
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        guard let universalLinkUrl = userActivity.webpageURL else {
            return false
        }

        return deepLinkHandler.handleUniversalLinkDeepLink(universalLinkUrl)
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

    // In-app message produces an error - preventing message from appearing to the user
    nonisolated func errorWithMessage(message: InAppMessage) {
        CustomerIO.shared.track(
            name: "inapp error",
            properties: ["delivery-id": message.deliveryId ?? "(none)", "message-id": message.messageId]
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

// =============================================================================
// === TESTING-ONLY === geofence-testing branch only — must not merge.
// Listens for `cioGeofenceTransitionForTesting` posted by `GeofenceEventTracker`
// (testing-only hook in the SDK) and shows a local UNNotification per
// transition. Paired with the mock in `Sources/Location/Geofence/Api/GeofenceApiService.swift`.
// =============================================================================
enum GeofenceTestNotifier {
    private static let notificationName = Notification.Name("cioGeofenceTransitionForTesting")
    // Testing-only: install() runs once on main thread from AppDelegate.
    nonisolated(unsafe) private static var observerToken: NSObjectProtocol?

    static func install() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        observerToken = NotificationCenter.default.addObserver(
            forName: notificationName,
            object: nil,
            queue: .main
        ) { notification in
            postLocalNotification(notification)
        }
    }

    private static func postLocalNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let geofenceId = userInfo["geofenceId"] as? String,
              let transition = userInfo["transition"] as? String
        else {
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "Geofence \(transition.uppercased())"
        content.body = "id=\(geofenceId)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "\(geofenceId)-\(transition)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

// =============================================================================
// === TESTING-ONLY === geofence-testing branch only — must not merge.
// Mirrors every SDK log line to a file in the app's Documents directory.
//
// File: <App Sandbox>/Documents/cio-logs-<yyyyMMdd-HHmmss>.log
// Pull: Xcode → Window → Devices and Simulators → select app → Download Container,
//       then inspect <Container>/AppData/Documents/cio-logs-*.log
//
// setLogDispatcher REPLACES the default systemLogger path, so we re-emit to
// `print` ourselves to keep Xcode console output active.
// =============================================================================
enum SdkFileLogger {
    nonisolated(unsafe) private static var fileURL: URL?
    private static let lock = NSLock()

    private static let fileTimestampFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let lineTimestampFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    static func install() {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let timestamp = fileTimestampFormat.string(from: Date())
        let logFile = documentsDir.appendingPathComponent("cio-logs-\(timestamp).log")
        fileURL = logFile
        FileManager.default.createFile(atPath: logFile.path, contents: nil)

        // App has its own DIGraphShared (shadowing); the SDK's lives in CioInternalCommon.
        CioInternalCommon.DIGraphShared.shared.logger.setLogDispatcher { level, message in
            print("[CIO] \(message)")
            let line = "\(lineTimestampFormat.string(from: Date())) \(level) \(message)\n"
            lock.lock()
            defer { lock.unlock() }
            guard let data = line.data(using: .utf8),
                  let handle = try? FileHandle(forWritingTo: logFile)
            else {
                return
            }
            defer { handle.closeFile() }
            handle.seekToEndOfFile()
            handle.write(data)
        }
        print("[CIO] SDK logs mirroring to \(logFile.path)")
    }
}
