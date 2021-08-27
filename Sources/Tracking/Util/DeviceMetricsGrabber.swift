import Foundation

internal enum DeviceMetricsGrabber {
    static var appBundleId: String? {
        Bundle.main.bundleIdentifier
    }
}
