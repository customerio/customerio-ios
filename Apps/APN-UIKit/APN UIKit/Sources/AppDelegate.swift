import CioTracking
import Foundation
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        CustomerIO.initialize(siteId: "", apiKey: "", region: .US, configure: nil)

        return true
    }
}
