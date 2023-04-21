import SwiftUI

@main
struct MainApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .accentColor(Color("AccentColor")) // sets Color.accentColor for all children
        }
    }
}
