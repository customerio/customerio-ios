import Foundation

protocol DeviceMetricsGrabber: AutoMockable {
    var appBundleId: String? { get }
}

// sourcery: InjectRegisterShared = "DeviceMetricsGrabber"
class DeviceMetricsGrabberImpl: DeviceMetricsGrabber {
    var appBundleId: String? {
        Bundle.main.bundleIdentifier
    }
}
