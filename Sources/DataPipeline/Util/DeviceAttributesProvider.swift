import CioInternalCommon
import Foundation

protocol DeviceAttributesProvider: AutoMockable {
    func getDefaultDeviceAttributes(onComplete: @escaping ([String: Any]) -> Void)
}
// sourcery: InjectRegister = "DeviceAttributesProvider"
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
            "cioSdkVersion": deviceInfo.sdkVersion,
            "appVersion": deviceInfo.customerAppVersion,
            "deviceLocale": deviceInfo.deviceLocale,
            "deviceManufacturer": deviceInfo.deviceManufacturer
        ]
        if let deviceModel = deviceInfo.deviceModel {
            deviceAttributes["deviceModel"] = deviceModel
        }
        if let deviceOsVersion = deviceInfo.osVersion {
            deviceAttributes["deviceOS"] = deviceOsVersion
        }
        deviceInfo.isPushSubscribed { isSubscribed in
            deviceAttributes["pushEnabled"] = String(isSubscribed)

            onComplete(deviceAttributes)
        }
    }
}
