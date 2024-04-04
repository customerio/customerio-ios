import SwiftUI

@main
struct VisionOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    let viewModel = ViewModel()
    var body: some Scene {
        WindowGroup {
            MainScreen()
                .environmentObject(viewModel)
                .onAppear {
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { success, error in
                        if !success {
                            print("NotificationError: \(String(describing: error))")
                        }
                    }
                }
        }
    }
}
