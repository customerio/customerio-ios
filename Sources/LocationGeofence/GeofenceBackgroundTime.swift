import CioInternalCommon
import Foundation

enum GeofenceBackgroundTime {
    static func runner(name: String) -> BackgroundTaskRunner {
        #if canImport(UIKit)
        UIKitBackgroundTaskRunner(name: name)
        #else
        NoBackgroundTaskRunner()
        #endif
    }
}
