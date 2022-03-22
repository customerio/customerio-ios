import CioTracking
import Foundation

internal protocol DeviceAttributesProvider: AutoMockable {
    func getDefaultDeviceAttributes(onComplete: @escaping ([String: Any]) -> Void)
}

// sourcery: InjectRegister = "DeviceAttributesProvider"
internal class SdkDeviceAttributesProvider: DeviceAttributesProvider {
    private let sdkConfigStore: SdkConfigStore
    private let deviceInfo: DeviceInfo

    init(diTracking: DITracking) {
        self.sdkConfigStore = diTracking.sdkConfigStore
        self.deviceInfo = diTracking.deviceInfo
    }

    func getDefaultDeviceAttributes(onComplete: @escaping ([String: Any]) -> Void) {
        if !sdkConfigStore.config.autoTrackDeviceAttributes {
            onComplete([:])
            return
        }

        var deviceAttributes = [
            "cio_sdk_version": deviceInfo.sdkVersion,
            "app_version": deviceInfo.customerAppVersion,
            "device_locale": deviceInfo.deviceLocale
        ]
        if let deviceModel = deviceInfo.deviceModel {
            deviceAttributes["device_model"] = deviceModel
        }
        if let deviceOs = deviceInfo.osInfo {
            deviceAttributes["device_os"] = deviceOs
        }
        deviceInfo.isPushSubscribed { isSubscribed in
            deviceAttributes["push_enabled"] = String(isSubscribed)

            onComplete(deviceAttributes)
        }
    }
}
