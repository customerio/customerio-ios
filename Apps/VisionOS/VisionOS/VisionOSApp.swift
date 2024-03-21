import SwiftUI

@main
struct VisionOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup {
            MainScreen()
        }
    }
}
