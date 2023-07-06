import SwiftUI

@main
struct MainApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    @StateObject var userManager: UserManager = .init()
    @StateObject var pendingDeepLinkUtil: PendingDeepLink = .shared

    @State private var openedDeepLinkUrl: URL?

    var body: some Scene {
        WindowGroup {
            HStack {
                if userManager.isUserLoggedIn {
                    DashboardView()
                        .environmentObject(userManager)
                } else {
                    LoginView()
                        .environmentObject(userManager)
                }
            }.accentColor(Color("AccentColor")) // sets Color.accentColor for all children
                .onChange(of: scenePhase) { newScenePhase in // handle when an app is not in the foreground, but will after the push gets clicked
                    if newScenePhase == .active { // app is now in the foreground
                        checkForPendingDeepLink()
                    }
                }
                .onChange(of: pendingDeepLinkUtil.pendingDeepLinkAvailable) { _ in // handle when an app is already in the foreground.
                    checkForPendingDeepLink()
                }
                .onOpenURL { deepLink in // This function is how to implement deep links in a Swift UI app.
                    // This app opens deep links using Universal Links and app scheme deep links.
                    //
                    // Universal Links: Any URL that begins with `https://ciosample.page.link`...
                    // App scheme: Any URL that begins with `cocoapods-fcm://`...
                    //
                    // ...will open the app and display the deep link in a pop-up.
                    openedDeepLinkUrl = deepLink
                }.alert(isPresented: Binding<URL>.notNil(openedDeepLinkUrl)) {
                    print("Deep link!! \(openedDeepLinkUrl!.absoluteString)")

                    // The openedDeepLink is consistently being set when I expect it to. However, Alert is not being shown as I expect it. Therefore, I say that this implementation of handling deep links is working, but we are getting weird Swift UI behavior. In another sample app update, we changed away from using Alerts so I will leave this for now.
                    return Alert(
                        title: Text("Deep link opened!"),
                        message: Text(openedDeepLinkUrl!.absoluteString),
                        dismissButton: .default(Text("OK"))
                    )
                }
        }
    }

    private func checkForPendingDeepLink() {
        if let deepLink = pendingDeepLinkUtil.getAndResetDeepLink() {
            openedDeepLinkUrl = deepLink.url
        }
    }
}
