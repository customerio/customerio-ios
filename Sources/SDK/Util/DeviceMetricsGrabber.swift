import Foundation

internal enum DeviceMetricsGrabber {
    static var appBundleId: String? {
        Bundle.main.infoDictionary?[kCFBundleNameKey as String] as? String
    }
}
