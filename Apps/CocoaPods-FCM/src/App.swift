import SwiftUI
import CioDataPipelines

enum NavScreen: Int {
    case inAppDemo, bannerDemo, contentDemo
}


@ViewBuilder
func rootScrren(navPath: Binding<[NavScreen]>, userManager: UserManager) -> some View {
    ZStack {
        Rectangle()
            .onTapGesture(count: 2) {
                navPath.wrappedValue.append(.inAppDemo)
            }
            .foregroundStyle(.background)
            
        DashboardView()
            .environmentObject(userManager)
    }
}

@ViewBuilder
func demo(screen: NavScreen, navPath: Binding<[NavScreen]>) -> some View {
    switch screen {
        case .inAppDemo:
            InlineInAppView(navPath: navPath)
        case .bannerDemo:
            TopBannerDemo()
        case .contentDemo:
            ContentDemo(navPath: navPath)
    }
}

@main
struct MainApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject var userManager: UserManager = .init()

    @State private var settingsScreen: SettingsView?
    
    @State private var navPath: [NavScreen] = []

    var body: some Scene {
        WindowGroup {
            Group {
                if let settingsScreen = settingsScreen {
                    settingsScreen
                        .environmentObject(userManager)
                } else if userManager.isUserLoggedIn {
                    NavigationStack(path: $navPath) {
                        rootScrren(navPath: $navPath, userManager: userManager)
                            .navigationDestination(for: NavScreen.self) { screen in
                                switch screen {
                                    case .inAppDemo:
                                        InlineInAppView(navPath: $navPath)
                                    case .bannerDemo:
                                        TopBannerDemo()
                                    case .contentDemo:
                                        ContentDemo(navPath: $navPath)
                                }
                            }
                    }
                    
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
                            var cdpApiKey: String?

                            if let queryItems = urlComponents.queryItems {
                                siteId = queryItems.first { $0.name == "site_id" }?.value
                                cdpApiKey = queryItems.first { $0.name == "cdp_api_key" }?.value
                            }

                            settingsScreen = SettingsView(siteId: siteId, cdpApiKey: cdpApiKey) {
                                settingsScreen = nil
                            }
                        default: break
                        }
                    }
                }.onAppear {
                    CustomerIO.shared.track(name: "in-app-demo")
                    CustomerIO.shared.flush()
                }
        }
    }
}
