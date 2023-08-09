import SwiftUI

@main
struct MainApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

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
                .onOpenURL { deepLink in // This function is how to implement deep links in a Swift UI app.
                    // This app opens deep links using Universal Links and app scheme deep links.
                    //
                    // Universal Links: Any URL that begins with `https://ciosample.page.link`...
                    // App scheme: Any URL that begins with `cocoapods-fcm://`...
                    //
                    // ...will open the app and display the deep link in a pop-up.
                    //
                    // Suggestions for debugging why deep links aren't working: https://stackoverflow.com/questions/32751225/ios-universal-links-are-not-opening-in-app
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
                        case "dashboard":
                            settingsScreen = nil // as long as user is logged in, this will make dashboard show
                        case "settings":
                            var siteId: String?
                            var apiKey: String?
                            var trackingUrl: String?

                            if let queryItems = urlComponents.queryItems {
                                siteId = queryItems.first { $0.name == "site_id" }?.value
                                apiKey = queryItems.first { $0.name == "api_key" }?.value
                                trackingUrl = queryItems.first { $0.name == "tracking_url" }?.value
                            }

                            settingsScreen = SettingsView(siteId: siteId, apiKey: apiKey, trackingUrl: trackingUrl) {
                                settingsScreen = nil
                            }
                        default: break
                        }
                    }
                }
        }
    }
}
