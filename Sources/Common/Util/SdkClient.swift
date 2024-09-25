import Foundation

/// Protocol for representing SDK client.
/// This is used to identify source of the SDK client and its version.
/// e.g. iOS Client/1.0.0, React Native Client/1.0.0, etc.
public protocol SdkClient: AutoMockable, CustomStringConvertible {
    var source: String { get }
    var sdkVersion: String { get }
}

public extension SdkClient {
    /// Returns readable description of the SDK client that can be used in user agent.
    var description: String {
        "\(source) Client/\(sdkVersion)"
    }
}

// sourcery: InjectRegisterShared = "SdkClient"
// sourcery: InjectCustomShared
// sourcery: InjectSingleton
public class CustomerIOSdkClient: SdkClient {
    public let source: String
    public let sdkVersion: String

    convenience init(deviceInfo: DeviceInfo) {
        self.init(source: deviceInfo.osName ?? "iOS", sdkVersion: SdkVersion.version)
    }

    init(source: String, sdkVersion: String) {
        self.sdkVersion = sdkVersion
        self.source = source
    }
}

// Extension to provide custom SdkClient initialization in DIGraphShared.
extension DIGraphShared {
    var customSdkClient: SdkClient {
        CustomerIOSdkClient(deviceInfo: deviceInfo)
    }
}
