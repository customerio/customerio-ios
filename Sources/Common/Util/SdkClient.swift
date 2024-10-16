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

    /// Convenience initializer to create `CustomerIOSdkClient` from `DeviceInfo`.
    convenience init(deviceInfo: DeviceInfo) {
        self.init(source: deviceInfo.osName ?? "iOS", sdkVersion: SdkVersion.version)
    }

    /// Initializes `CustomerIOSdkClient` with source and sdk version.
    /// If source or sdk version is empty, it will default to "iOS" and current SDK version.
    public init(source: String, sdkVersion: String) {
        guard !source.isBlankOrEmpty(), !sdkVersion.isBlankOrEmpty() else {
            self.source = "iOS"
            self.sdkVersion = SdkVersion.version
            return
        }

        self.source = source
        self.sdkVersion = sdkVersion
    }
}

// Extension to provide custom SdkClient initialization in DIGraphShared.
extension DIGraphShared {
    var customSdkClient: SdkClient {
        CustomerIOSdkClient(deviceInfo: deviceInfo)
    }

    /// SDK client for NSE. It is not injected as dependency, but can be accessed
    /// using `DIGraphShared.shared.nseSdkClient`.
    var nseSdkClient: SdkClient {
        CustomerIOSdkClient(source: "NSE", sdkVersion: SdkVersion.version)
    }
}
