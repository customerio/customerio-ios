@testable import CioDataPipelines
@testable import CioInternalCommon

extension DeviceInfoMock {
    @discardableResult
    func configureWithMockData(
        osName: String? = "iOS",
        sdkVersion: String? = "3.0.0",
        customerAppVersion: String? = "1.2.3",
        deviceLocale: String? = String.random,
        deviceManufacturer: String? = String.random,
        isPushSubscribed: Bool = true
    ) -> [String: Any] {
        underlyingOsName = osName
        underlyingSdkVersion = sdkVersion
        underlyingCustomerAppVersion = customerAppVersion
        underlyingDeviceLocale = deviceLocale
        underlyingDeviceManufacturer = deviceManufacturer
        isPushSubscribedClosure = { $0(isPushSubscribed) }
        return getDefaultAttributes(isPushSubscribed: isPushSubscribed)
    }

    func getDefaultAttributes(isPushSubscribed: Bool = true) -> [String: Any] {
        var attributes: [String: Any] = [:]
        if let sdkVersion = underlyingSdkVersion {
            attributes["cio_sdk_version"] = sdkVersion
        }
        if let customerAppVersion = underlyingCustomerAppVersion {
            attributes["app_version"] = customerAppVersion
        }
        if let deviceLocale = underlyingDeviceLocale {
            attributes["device_locale"] = deviceLocale
        }
        if let deviceManufacturer = underlyingDeviceManufacturer {
            attributes["device_manufacturer"] = deviceManufacturer
        }
        if let deviceModel = underlyingDeviceModel {
            attributes["device_model"] = deviceModel
        }
        if let deviceOsVersion = underlyingOsVersion {
            attributes["device_os"] = deviceOsVersion
        }
        attributes["push_enabled"] = String(isPushSubscribed)
        return attributes
    }
}

extension DeviceAttributesProviderMock {
    func configureWithMockData(defaultAttributes: [String: Any] = [:]) {
        getDefaultDeviceAttributesClosure = { $0(defaultAttributes) }
    }
}

extension GlobalDataStoreMock {
    func configureWithMockData(token: String? = nil) {
        underlyingPushDeviceToken = token
    }
}
