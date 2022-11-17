import Common
import Foundation

internal protocol DeviceAttributesProvider: AutoMockable {
    func getDefaultDeviceAttributes(onComplete: @escaping ([String: Any]) -> Void)
}

// sourcery: InjectRegister = "DeviceAttributesProvider"
internal class SdkDeviceAttributesProvider: DeviceAttributesProvider {
    private let sdkConfigStore: SdkConfigStore
    private let deviceInfo: DeviceInfo

    init(sdkConfigStore: SdkConfigStore, deviceInfo: DeviceInfo) {
        self.sdkConfigStore = sdkConfigStore
        self.deviceInfo = deviceInfo
    }

    func getDefaultDeviceAttributes(onComplete: @escaping ([String: Any]) -> Void) {
        if !sdkConfigStore.config.autoTrackDeviceAttributes {
            onComplete([:])
            return
        }

        var deviceAttributes = [
            "cio_sdk_version": getSdkVersionAttribute(),
            "app_version": deviceInfo.customerAppVersion,
            "device_locale": deviceInfo.deviceLocale,
            "device_manufacturer": deviceInfo.deviceManufacturer
        ]
        if let deviceModel = deviceInfo.deviceModel {
            deviceAttributes["device_model"] = deviceModel
        }
        if let deviceOsVersion = deviceInfo.osVersion {
            deviceAttributes["device_os"] = deviceOsVersion
        }
        deviceInfo.isPushSubscribed { isSubscribed in
            deviceAttributes["push_enabled"] = String(isSubscribed)

            onComplete(deviceAttributes)
        }
    }

    internal func getSdkVersionAttribute() -> String {
        var sdkVersion = deviceInfo.sdkVersion

        // Allow SDK wrapper to override the SDK version
        if let sdkWrapperConfig = sdkConfigStore.config._sdkWrapperConfig {
            sdkVersion = sdkWrapperConfig.version
        }

        return sdkVersion
    }
}
