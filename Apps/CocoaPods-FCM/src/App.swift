import SwiftUI

@main
struct MainApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject var userManager: UserManager = .init()

    var body: some Scene {
        WindowGroup {
            if userManager.isUserLoggedIn {
                DashboardView()
                    .environmentObject(userManager)
                    .accentColor(Color("AccentColor")) // sets Color.accentColor for all children
            } else {
                LoginView()
                    .environmentObject(userManager)
                    .accentColor(Color("AccentColor")) // sets Color.accentColor for all children
            }
        }
    }
}
