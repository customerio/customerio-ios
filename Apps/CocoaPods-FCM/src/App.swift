import CioDataPipelines
import CioLiveActivities
import CioMessagingPushFCM
import SwiftUI

@main
struct MainApp: App {
    // Default option, without CIO integration
//    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // Use this option if you don't have a need to extend `CioAppDelegateWrapper`
    // The adaptor keeps application-global initialization, token, and notification callbacks in
    // UIApplicationDelegate. UI activation routing remains exclusively in SwiftUI's onOpenURL.
    @UIApplicationDelegateAdaptor(CioAppDelegateWrapper<AppDelegate>.self) private var appDelegate

    // Use this option if you need to extend `CioAppDelegateWrapper`: class AppDelegateWithCioIntegration: CioAppDelegateWrapper<AppDelegate> {}
//    @UIApplicationDelegateAdaptor(AppDelegateWithCioIntegration.self) private var appDelegate

    @StateObject var userManager: UserManager = .init()

    @State private var settingsScreen: SettingsView?

    private let lifecycleCoordinator = CioAppLifecycleCoordinator(hostTopology: .swiftUILifecycle)

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
                .onOpenURL { incomingURL in
                    _ = lifecycleCoordinator.handleSwiftUIOpenURL(incomingURL) { route(url: $0) }
                }
        }
    }

    private func route(url incomingURL: URL) -> Bool {
        // A Customer.io Live Activity URL reports the exact opened delivery before routing its
        // redirect. A delivery-only URL is handled even when there is no redirect.
        guard let deepLink = CustomerIO.liveActivities.handleWidgetUrl(incomingURL) else {
            return true
        }
        guard let urlComponents = URLComponents(url: deepLink, resolvingAgainstBaseURL: false) else {
            return false
        }

        let command: String
        if urlComponents.scheme == "https" {
            command = urlComponents.path.replacingOccurrences(of: "/", with: "")
        } else {
            command = urlComponents.host ?? ""
        }

        switch command {
        case "login":
            userManager.logout()
        case "dashboard":
            settingsScreen = nil
        case "settings":
            let siteId = urlComponents.queryItems?.first { $0.name == "site_id" }?.value
            let cdpApiKey = urlComponents.queryItems?.first { $0.name == "cdp_api_key" }?.value
            settingsScreen = SettingsView(siteId: siteId, cdpApiKey: cdpApiKey) {
                settingsScreen = nil
            }
        default:
            return false
        }
        return true
    }
}
