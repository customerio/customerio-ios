import CioInternalCommon
import Foundation

/// Device attribute keys the SDK reads back after sending.
enum DeviceAttributeKey {
    static let pushEnabled = "push_enabled"
    static let apnsEnvironment = "apns_environment"
}

protocol DeviceAttributesProvider: AutoMockable {
    func getDefaultDeviceAttributes(onComplete: @escaping ([String: Any]) -> Void)
}

// sourcery: InjectRegisterShared = "DeviceAttributesProvider"
class SdkDeviceAttributesProvider: DeviceAttributesProvider {
    private let deviceInfo: DeviceInfo
    private let sdkClient: SdkClient
    private let apnsEnvironmentProvider: ApnsEnvironmentProvider
    private var moduleConfig: DataPipelineConfigOptions {
        DataPipeline.moduleConfig
    }

    init(deviceInfo: DeviceInfo, sdkClient: SdkClient, apnsEnvironmentProvider: ApnsEnvironmentProvider) {
        self.deviceInfo = deviceInfo
        self.sdkClient = sdkClient
        self.apnsEnvironmentProvider = apnsEnvironmentProvider
    }

    func getDefaultDeviceAttributes(onComplete: @escaping ([String: Any]) -> Void) {
        if !moduleConfig.autoTrackDeviceAttributes {
            onComplete([:])
            return
        }

        var deviceAttributes = [
            "cio_sdk_version": sdkClient.sdkVersion,
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
        if let apnsEnvironment = apnsEnvironmentProvider.environment {
            deviceAttributes[DeviceAttributeKey.apnsEnvironment] = apnsEnvironment.rawValue
        }
        deviceInfo.isPushSubscribed { isSubscribed in
            deviceAttributes[DeviceAttributeKey.pushEnabled] = String(isSubscribed)

            onComplete(deviceAttributes)
        }
    }
}
