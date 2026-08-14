import CioInternalCommon
import Foundation

/// Picks the background-task runner for geofence work: a real `UIApplication` assertion in the
/// app, a no-op where `UIApplication` is unavailable (non-UIKit platforms).
enum GeofenceBackgroundTime {
    static func runner(name: String) -> BackgroundTaskRunner {
        #if canImport(UIKit)
        UIKitBackgroundTaskRunner(name: name)
        #else
        NoBackgroundTaskRunner()
        #endif
    }
}
