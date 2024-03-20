import SwiftUI

@main
struct VisionOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    let viewModel = ViewModel()
    var body: some Scene {
        WindowGroup {
            MainScreen()
                .environmentObject(viewModel)
        }
    }
}
