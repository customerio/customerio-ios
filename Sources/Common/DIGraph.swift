import Foundation

public class DIGraph: DIManager {
    public let sdkConfig: SdkConfig

    public init(sdkConfig: SdkConfig) {
        self.sdkConfig = sdkConfig
    }

    public var overrides: [String: Any] = [:]
    public var singletons: [String: Any] = [:]
}
