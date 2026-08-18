import CioDataPipelines
import CioFirebaseWrapper
import CioInternalCommon
import CioLiveActivities
import CioLiveActivities_Attributes
import CioLiveActivities_Templates
import CioLocation
import CioLocationGeofence
import CioMessagingInApp
import CioMessagingPush
import CioMessagingPushFCM
import FirebaseCore
import Foundation
import SampleAppsCommon
import UIKit

private let sampleLifecycleTraceRecorder = LifecycleTraceHarness.configureFromEnvironment(
    sink: ConsoleLifecycleTraceSink()
)
private let sampleLifecycleProbeObserver = sampleLifecycleTraceRecorder.map { _ in
    LifecycleTracePlatformProbeObserver()
}

class AppDelegate: NSObject, UIApplicationDelegate {
    /*
     Next line of code is used for testing how Firebase behaves when another object is set as the delegate for `UNUserNotificationCenter`.
     This is not necessary for the Customer.io SDK to work.
     */
//    let anotherPushEventHandler = AnotherPushEventHandler()

    // Existing SDK initialization remains in this delegate seat; tracing does not split or reorder it.
    // swiftlint:disable:next function_body_length
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        _ = sampleLifecycleTraceRecorder
        _ = sampleLifecycleProbeObserver
        LifecycleTraceHarness.startScenario()
        recordLaunchCallback(application, launchOptions: launchOptions)

        // Follow setup guide for setting up FCM push: https://firebase.google.com/docs/cloud-messaging/ios/client
        // The FCM SDK provides a device token to the app that you then send to the Customer.io SDK.

        // Initialize the Firebase SDK.
        FirebaseApp.configure()

        let appSetSettings = CioSettingsManager().appSetSettings
        let siteId = appSetSettings?.siteId ?? BuildEnvironment.CustomerIO.siteId
        let cdpApiKey = appSetSettings?.cdpApiKey ?? BuildEnvironment.CustomerIO.cdpApiKey

        // Configure and initialize the Customer.io SDK
        let config = SDKConfigBuilder(cdpApiKey: cdpApiKey)
            .region(Region.US)
            .migrationSiteId(siteId)
            .flushAt(appSetSettings?.flushAt ?? 10)
            .flushInterval(Double(appSetSettings?.flushInterval ?? 30))
            .autoTrackDeviceAttributes(appSetSettings?.trackDeviceAttributes ?? true)
            .deepLinkCallback { [self] (url: URL) in
                let urlEvidence = LifecycleTraceEvidence.observe(url: url)
                LifecycleTraceHarness.sharedRecorder?.record(
                    callback: .customerIORouteDeepLink,
                    owner: .customerIOSDK,
                    kind: .sdkRouting,
                    phase: .intent,
                    observations: urlEvidence
                )
                // You can call any method to process this furhter,
                // or redirect it to `application(_:continue:restorationHandler:)` for consistency, if you use deep-linking in Firebase
                let openLinkInHostAppActivity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
                openLinkInHostAppActivity.webpageURL = url
                let activityEvidence = LifecycleTraceEvidence.observe(userActivity: openLinkInHostAppActivity)
                LifecycleTraceHarness.sharedRecorder?.record(
                    callback: .hostRouteUserActivity,
                    owner: .host,
                    kind: .hostRouting,
                    phase: .intent,
                    observations: activityEvidence
                )
                let handled = routeUniversalLink(openLinkInHostAppActivity)
                LifecycleTraceHarness.sharedRecorder?.record(
                    callback: .hostRouteUserActivity,
                    owner: .host,
                    kind: .hostRouting,
                    phase: .result,
                    observations: activityEvidence,
                    LifecycleTraceEvidence.observe(routingResult: handled ? .handled : .unhandled)
                )
                LifecycleTraceHarness.sharedRecorder?.record(
                    callback: .customerIORouteDeepLink,
                    owner: .customerIOSDK,
                    kind: .sdkRouting,
                    phase: .result,
                    observations: urlEvidence,
                    LifecycleTraceEvidence.observe(routingResult: handled ? .handled : .unhandled)
                )
                LifecycleTraceHarness.endScenario(after: .hostUserActivityRoute)
                return handled
            }
        let logLevel = appSetSettings?.debugSdkMode
        if logLevel == nil || logLevel == true {
            config.logLevel(CioLogLevel.debug)
        }
        if let apiHost = appSetSettings?.apiHost, !apiHost.isEmpty {
            config.apiHost(apiHost)
        }
        if let cdnHost = appSetSettings?.cdnHost, !cdnHost.isEmpty {
            config.cdnHost(cdnHost)
        }
        config.addModule(LocationModule(config: LocationConfig(mode: .manual)))
        config.addModule(GeofenceModule())
        // Register Live Activities as an SDK-managed module. Both types are SDK-provided templates
        // rendered by the LiveActivityWidget extension; reach the API via `CustomerIO.liveActivities`.
        if #available(iOS 16.2, *) {
            config.addModule(LiveActivitiesModule(
                config: LiveActivityConfigBuilder()
                    .register(CIOSegmentsAttributes.self)
                    .register(CIOCountdownTimerAttributes.self)
                    .build()
            ))
        }
        CustomerIO.initialize(withConfig: config.build())

        // Initialize messaging features after initializing Customer.io SDK
        MessagingInApp
            .initialize(withConfig: MessagingInAppConfigBuilder(siteId: siteId, region: .US).build())
            .setEventListener(self)
        MessagingPushFCM.initialize(
            withConfig: MessagingPushConfigBuilder()
                .autoFetchDeviceToken(true)
                .autoTrackPushEvents(true)
                .showPushAppInForeground(true)
                .build()
        )

        /*
         Next line of code is used for testing how Firebase behaves when another object is set as the delegate for `UNUserNotificationCenter`.
         This is not necessary for the Customer.io SDK to work.
         */
//        UNUserNotificationCenter.current().delegate = anotherPushEventHandler

        /*
         Registers the `AppDelegate` class to handle when a push notification gets clicked.
         This line of code is optional and only required if you have custom code that needs to run when a push notification gets clicked on.
         Push notifications sent by Customer.io will be handled by the Customer.io SDK automatically, unless you disabled that feature.
         Therefore, this line of code is not required if you only want to handle push notifications sent by Customer.io.
         */
//        UNUserNotificationCenter.current().delegate = self

        return true
    }

    // MARK: MBL-2232 trace helpers (kept out of `didFinishLaunching` to respect function-length lint)

    private func recordLaunchCallback(_ application: UIApplication, launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        guard LifecycleTraceHarness.sharedRecorder?.scenario.isColdStart == true else { return }
        LifecycleTraceHarness.sharedRecorder?.record(
            callback: .applicationDidFinishLaunching,
            owner: .applicationDelegate,
            kind: .osCallback,
            phase: .entry,
            observations: LifecycleTraceEvidence.observe(applicationState: application.applicationState),
            LifecycleTraceEvidence.observe(launchOptions: launchOptions)
        )
    }

    // IMPORTANT: If FCM is used with enabled swizzling (default state) it will not call this method in SwiftUI based apps.
    //            Use `deepLinkCallback` on SDKConfigBuilder, as that works in all scenarios.
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([any UIUserActivityRestoring]?) -> Void) -> Bool {
        guard userActivity.webpageURL != nil else { return false }
        let shouldTrace = LifecycleTraceHarness.sharedRecorder?.hostTopology == .appDelegateOnly
        let routeEvidence = LifecycleTraceEvidence.observe(userActivity: userActivity)
        if shouldTrace {
            LifecycleTraceHarness.sharedRecorder?.record(
                callback: .applicationContinueUserActivity,
                owner: .applicationDelegate,
                kind: .osCallback,
                phase: .entry,
                observations: LifecycleTraceEvidence.observe(applicationState: application.applicationState),
                routeEvidence
            )
            LifecycleTraceHarness.sharedRecorder?.record(
                callback: .hostRouteUserActivity,
                owner: .host,
                kind: .hostRouting,
                phase: .intent,
                observations: routeEvidence
            )
        }
        let handled = routeUniversalLink(userActivity)
        if shouldTrace {
            LifecycleTraceHarness.sharedRecorder?.record(
                callback: .hostRouteUserActivity,
                owner: .host,
                kind: .hostRouting,
                phase: .result,
                observations: routeEvidence,
                LifecycleTraceEvidence.observe(routingResult: handled ? .handled : .unhandled)
            )
            LifecycleTraceHarness.endScenario(after: .hostUserActivityRoute)
        }
        return handled
    }

    private func routeUniversalLink(_ userActivity: NSUserActivity) -> Bool {
        guard userActivity.webpageURL != nil else {
            return false
        }
        // By returning `false` we are indicating to iOS that not no screen is shown in associateion to provided URL.
        // Same information is used by CIO `deepLinkCallback` to open URL in the browser
        return false
    }
}

/*
  The lines of code below are optional and only required if you:
  - want fine-grained control over whether notifications are shown in the foreground
  - have custom code that needs to run when a push notification gets clicked on.
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

extension AppDelegate: InAppEventListener {
    nonisolated func messageShown(message: InAppMessage) {
        CustomerIO.shared.track(
            name: "inapp shown",
            properties: ["delivery-id": message.deliveryId ?? "(none)", "message-id": message.messageId]
        )
    }

    nonisolated func messageDismissed(message: InAppMessage) {
        CustomerIO.shared.track(
            name: "inapp dismissed",
            properties: ["delivery-id": message.deliveryId ?? "(none)", "message-id": message.messageId]
        )
    }

    nonisolated func errorWithMessage(message: InAppMessage) {
        CustomerIO.shared.track(
            name: "inapp error",
            properties: ["delivery-id": message.deliveryId ?? "(none)", "message-id": message.messageId]
        )
    }

    nonisolated func messageActionTaken(message: InAppMessage, actionValue: String, actionName: String) {
        CustomerIO.shared.track(name: "inapp action", properties: [
            "delivery-id": message.deliveryId ?? "(none)",
            "message-id": message.messageId,
            "action-value": actionValue,
            "action-name": actionName
        ])
    }
}
