import Foundation

public protocol SdkClient: AutoMockable, CustomStringConvertible {
    var source: String { get }
    var sdkVersion: String { get }
}

public extension SdkClient {
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

    public static let SOURCE_IOS = "iOS"

    public static func create(source: String? = nil, sdkVersion: String? = nil) -> CustomerIOSdkClient {
        guard let source = source, !source.isBlankOrEmpty(),
              let sdkVersion = sdkVersion, !sdkVersion.isBlankOrEmpty()
        else {
            return CustomerIOSdkClient(source: SOURCE_IOS, sdkVersion: SdkVersion.version)
        }

        return CustomerIOSdkClient(source: source, sdkVersion: sdkVersion)
    }
}

extension DIGraphShared {
    var customSdkClient: SdkClient {
        CustomerIOSdkClient.create(source: deviceInfo.osName, sdkVersion: SdkVersion.version)
    }
}
