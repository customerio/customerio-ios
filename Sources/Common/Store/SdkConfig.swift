import Foundation

/// Defines configuration options for the Customer.io SDK.
///
/// Use `SDKConfigBuilder` for constructing its instances. For detailed usage, see builder class documentation.
public struct SdkConfig {

    /// Server key
    public let cdpApiKey: String

    /// Host settings
    public let region: Region

    public let logLevel: CioLogLevel
    public let moduleTypes: [CIOModule.Type]
    private let extensionValues: [String: Any]

    
    init(
        cdpApiKey: String,
        region: Region = .US,
        logLevel: CioLogLevel? = nil,
        moduleTypes: [CIOModule.Type] = [],
        extensionValues: [String: Any] = [:],
    ) {
        self.cdpApiKey = cdpApiKey
        self.region = region
        self.logLevel = logLevel ?? CioLogLevel.error
        self.moduleTypes = moduleTypes
        self.extensionValues = extensionValues
    }
    
    @_spi(Module)
    public func extensionValue<T>(for key: String) -> T? {
        extensionValues[key] as? T
    }

    @_spi(Module)
    public func extensionValue<T>(for key: String, default defaultValue: T) -> T {
        extensionValues[key] as? T ?? defaultValue
    }


}
