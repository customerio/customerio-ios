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
        var deviceAttributes: [String: String] = [:]
        // Sent even when automatic device attributes are off, as the backend picks the APNs environment from it
        if let apnsEnvironment = apnsEnvironmentProvider.environment {
            deviceAttributes[DeviceAttributeKey.apnsEnvironment] = apnsEnvironment.rawValue
        }

        if !moduleConfig.autoTrackDeviceAttributes {
            onComplete(deviceAttributes)
            return
        }

        deviceAttributes["cio_sdk_version"] = sdkClient.sdkVersion
        deviceAttributes["app_version"] = deviceInfo.customerAppVersion
        deviceAttributes["device_locale"] = deviceInfo.deviceLocale
        deviceAttributes["device_manufacturer"] = deviceInfo.deviceManufacturer
        if let deviceModel = deviceInfo.deviceModel {
            deviceAttributes["device_model"] = deviceModel
        }
        if let deviceOsVersion = deviceInfo.osVersion {
            deviceAttributes["device_os"] = deviceOsVersion
        }
        deviceInfo.isPushSubscribed { isSubscribed in
            deviceAttributes[DeviceAttributeKey.pushEnabled] = String(isSubscribed)

            onComplete(deviceAttributes)
        }
    }
}
