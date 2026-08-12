import CioDataPipelines
import CioLiveActivities
import CioMessagingPushFCM
import SampleAppsCommon
import SwiftUI

@main
struct MainApp: App {
    // Default option, without CIO integration
//    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // Use this option if you don't have a need to extend `CioAppDelegateWrapper`
    @UIApplicationDelegateAdaptor(CioAppDelegateWrapper<AppDelegate>.self) private var appDelegate

    // Use this option if you need to extend `CioAppDelegateWrapper`: class AppDelegateWithCioIntegration: CioAppDelegateWrapper<AppDelegate> {}
//    @UIApplicationDelegateAdaptor(AppDelegateWithCioIntegration.self) private var appDelegate

    @StateObject var userManager: UserManager = .init()

    @State private var settingsScreen: SettingsView?

    var body: some Scene {
        WindowGroup {
            HStack {
                if let settingsScreen = settingsScreen {
                    settingsScreen
                        .environmentObject(userManager)
                } else if userManager.isUserLoggedIn {
                    DashboardView()
                        .environmentObject(userManager)
                } else {
                    LoginView()
                        .environmentObject(userManager)
                }
            }.accentColor(Color("AccentColor")) // sets Color.accentColor for all children
                .onOpenURL { incomingURL in // This function is how to implement deep links in a Swift UI app.
                    let shouldTrace = LifecycleTraceEvidence.isTraceableURLRoute(incomingURL)
                    let routeEvidence = LifecycleTraceEvidence.observe(url: incomingURL)
                    if shouldTrace {
                        LifecycleTraceHarness.sharedRecorder?.record(
                            callback: .swiftUIOnOpenURL,
                            owner: .swiftUIScene,
                            kind: .osCallback,
                            phase: .entry,
                            observations: routeEvidence
                        )
                    }
                    // A tap on a Customer.io Live Activity arrives as a CIO tracking URL. Hand it to
                    // the SDK first: it reports the `opened` metric for the exact delivery that was on
                    // screen and returns the customer's deep link to navigate to (nil if there is
                    // none). Any non-Customer.io URL is returned unchanged.
                    if shouldTrace {
                        LifecycleTraceHarness.sharedRecorder?.record(
                            callback: .hostRouteURL,
                            owner: .host,
                            kind: .hostRouting,
                            phase: .intent,
                            observations: routeEvidence
                        )
                    }
                    let isCustomerIORoute = LifecycleTraceEvidence.isCustomerIOLiveActivityRoute(incomingURL)
                    if shouldTrace, isCustomerIORoute {
                        LifecycleTraceHarness.sharedRecorder?.record(
                            callback: .customerIORouteDeepLink,
                            owner: .customerIOSDK,
                            kind: .sdkRouting,
                            phase: .intent,
                            observations: routeEvidence
                        )
                    }
                    let deepLinkFromWidgetUrl = CustomerIO.liveActivities.handleWidgetUrl(incomingURL)
                    if shouldTrace, isCustomerIORoute {
                        LifecycleTraceHarness.sharedRecorder?.record(
                            callback: .customerIORouteDeepLink,
                            owner: .customerIOSDK,
                            kind: .sdkRouting,
                            phase: .result,
                            observations: routeEvidence,
                            LifecycleTraceEvidence.observe(routingResult: MainApp.widgetRoutingResult(original: incomingURL, destination: deepLinkFromWidgetUrl))
                        )
                    }
                    guard let deepLink = deepLinkFromWidgetUrl else {
                        if shouldTrace {
                            MainApp.recordHostRouteResult(evidence: routeEvidence, handled: true)
                        }
                        return
                    }
                    // This app opens deep links using Universal Links and app scheme deep links.
                    //
                    // Universal Links: Any URL that begins with `https://ciosample.page.link`...
                    // App scheme: Any URL that begins with `cocoapods-fcm://`...
                    //
                    // ...will open the app and display the deep link in a pop-up.
                    //
                    // Suggestions for debugging why deep links aren't working: https://stackoverflow.com/questions/32751225/ios-universal-links-are-not-opening-in-app
                    var handled = false
                    if let urlComponents = URLComponents(url: deepLink, resolvingAgainstBaseURL: false) {
                        var command = ""
                        if urlComponents.scheme == "https" { // universal link
                            // path will start with a / character
                            command = urlComponents.path.replacingOccurrences(of: "/", with: "")
                        } else {
                            command = urlComponents.host!
                        }

                        switch command {
                        case "login":
                            userManager.logout() // will force the app's UI to navigate back to login screen
                            handled = true
                        case "dashboard":
                            settingsScreen = nil // as long as user is logged in, this will make dashboard show
                            handled = true
                        case "settings":
                            var siteId: String?
                            var cdpApiKey: String?

                            if let queryItems = urlComponents.queryItems {
                                siteId = queryItems.first { $0.name == "site_id" }?.value
                                cdpApiKey = queryItems.first { $0.name == "cdp_api_key" }?.value
                            }

                            settingsScreen = SettingsView(siteId: siteId, cdpApiKey: cdpApiKey) {
                                settingsScreen = nil
                            }
                            handled = true
                        default: break
                        }
                    }
                    if shouldTrace {
                        MainApp.recordHostRouteResult(evidence: routeEvidence, handled: handled)
                    }
                }
        }
    }

    // MARK: MBL-2232 trace helpers

    // `handleWidgetUrl` returns nil for a consumed CIO tracking URL without a redirect, the
    // unwrapped deep link for one with a redirect, and the input unchanged for non-CIO URLs.
    private static func widgetRoutingResult(original: URL, destination: URL?) -> LifecycleTraceRoutingResult {
        guard let destination = destination else { return .handled }
        return destination == original ? .unhandled : .redirect
    }

    private static func recordHostRouteResult(evidence: LifecycleTraceObservation, handled: Bool) {
        LifecycleTraceHarness.sharedRecorder?.record(
            callback: .hostRouteURL,
            owner: .host,
            kind: .hostRouting,
            phase: .result,
            observations: evidence,
            LifecycleTraceEvidence.observe(routingResult: handled ? .handled : .unhandled)
        )
        LifecycleTraceHarness.endScenario(after: .hostURLRoute)
    }
}
