import CioInternalCommon
import Foundation

protocol DeviceAttributesProvider: AutoMockable {
    func getDefaultDeviceAttributes(onComplete: @escaping ([String: Any]) -> Void)
}

// sourcery: InjectRegisterShared = "DeviceAttributesProvider"
class SdkDeviceAttributesProvider: DeviceAttributesProvider {
    private let deviceInfo: DeviceInfo
    private var moduleConfig: DataPipelineConfigOptions {
        DataPipeline.moduleConfig
    }

    init(deviceInfo: DeviceInfo) {
        self.deviceInfo = deviceInfo
    }

    func getDefaultDeviceAttributes(onComplete: @escaping ([String: Any]) -> Void) {
        if !moduleConfig.autoTrackDeviceAttributes {
            onComplete([:])
            return
        }

        var deviceAttributes = [
            "cio_sdk_version": deviceInfo.sdkVersion,
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
}
