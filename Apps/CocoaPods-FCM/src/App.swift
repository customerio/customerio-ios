import SwiftUI

@main
struct MainApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject var userManager: UserManager = .init()

    @State private var openedDeepLinkUrl: URL?
    @State private var showOpenedDeepLink: Bool = false // I would like for this value to be set based on openedDeepLinkUrl != nil but can't figure that out yet.

    var body: some Scene {
        WindowGroup {
            HStack {
                if userManager.isUserLoggedIn {
                    DashboardView()
                        .environmentObject(userManager)
                        .accentColor(Color("AccentColor")) // sets Color.accentColor for all children
                } else {
                    LoginView()
                        .environmentObject(userManager)
                        .accentColor(Color("AccentColor")) // sets Color.accentColor for all children
                }
            }.onOpenURL { deepLink in
                // App opens via Universal Link.
                // Any URL that begins with `https://ciosample.page.link` will open this app and display the URL to you in a pop-up.
                openedDeepLinkUrl = deepLink
                showOpenedDeepLink = true
            }.alert(isPresented: $showOpenedDeepLink) {
                Alert(
                    title: Text("Deep link opened!"),
                    message: Text(openedDeepLinkUrl!.absoluteString),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }
}
