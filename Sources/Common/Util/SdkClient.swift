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
public struct CustomerIOSdkClient: SdkClient {
    public let source: String
    public let sdkVersion: String

    private init(source: String, sdkVersion: String) {
        self.source = source
        self.sdkVersion = sdkVersion
    }

    // Default source for native iOS SDK
    private static let SOURCE_IOS = "iOS"

    /// Creates a new instance of `CustomerIOSdkClient` with provided source and sdk version.
    /// If source or sdk version is nil or empty, it will use default values.
    /// - Parameters:
    ///  - source: Source of SDK client.
    ///  - sdkVersion: Version of SDK client.
    /// - Returns: A new instance of `CustomerIOSdkClient`.
    public static func create(source: String? = nil, sdkVersion: String? = nil) -> CustomerIOSdkClient {
        guard let source = source, !source.isBlankOrEmpty(),
              let sdkVersion = sdkVersion, !sdkVersion.isBlankOrEmpty()
        else {
            return CustomerIOSdkClient(source: SOURCE_IOS, sdkVersion: SdkVersion.version)
        }

        return CustomerIOSdkClient(source: source, sdkVersion: sdkVersion)
    }
}

// Extension to provide custom SdkClient initialization in DIGraphShared.
extension DIGraphShared {
    var customSdkClient: SdkClient {
        CustomerIOSdkClient.create(source: deviceInfo.osName, sdkVersion: SdkVersion.version)
    }
}
