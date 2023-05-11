import SwiftUI

@main
struct MainApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject var userManager: UserManager = .init()

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
                .onOpenURL { deepLink in // This function is how to implement deep links in a SwiftUIU app.
                    // This app opens deep links using Universal Links and app scheme deep links.
                    //
                    // Universal Links: Any URL that begins with `https://ciosample.page.link`...
                    // App scheme: Any URL that begins with `cocoapods-fcm://`...
                    //
                    // ...will open the app and display the deep link in a pop-up.
                    openedDeepLinkUrl = deepLink
                }.alert(isPresented: Binding<URL>.notNil(openedDeepLinkUrl)) {
                    Alert(
                        title: Text("Deep link opened!"),
                        message: Text(openedDeepLinkUrl!.absoluteString),
                        dismissButton: .default(Text("OK"))
                    )
                }
        }
    }
}
