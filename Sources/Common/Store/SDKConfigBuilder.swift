//
//  SDKConfigBuilder.swift
//  Customer.io
//
//  Created by Holly Schilling on 2/11/26.
//


/// Builder class designed to facilitate the creation of `SdkConfig` and `DataPipelineConfigOptions`.
/// The builder pattern allows for a fluent and intuitive way to set up configuration options for
/// the SDK, ensuring all required and optional settings are appropriately configured before the
/// SDK is initialized.
///
/// **Usage Example:**
///
/// ```
/// let config = SDKConfigBuilder(cdpApiKey: "your_cdp_api_key")
///   .logLevel(.debug)
///   .flushAt(30)
///   // additional configuration as needed...
///   .build()
/// // Use `config` for initializing the SDK...
/// ```
public class SDKConfigBuilder {
    // helper configuration options to ease setting up other configurations such as `apiHost` and `cdnHost`
    private var region: Region = .US

    // configuration options for SdkConfig
    private var logLevel: CioLogLevel = .error

    // configuration options for DataPipelineConfigOptions
    private let cdpApiKey: String

    /// Initializes new `SDKConfigBuilder` with required configuration options.
    /// - Parameters:
    ///   - cdpApiKey: Customer.io Data Pipeline API Key
    public init(cdpApiKey: String) {
        self.cdpApiKey = cdpApiKey
    }
    
    private var extensionValues: [String: Any] = [:]
    private var enrolledModules: [ObjectIdentifier: CIOModule.Type] = [:]
    
    @_spi(Module)
    public func setExtensionValue<T>(_ value: T, forKey key: String) -> Self {
        extensionValues[key] = value
        return self
    }
    
    @_spi(Module)
    public func enrollModule(_ moduleType: CIOModule.Type) -> SDKConfigBuilder {
        let identifier = ObjectIdentifier(moduleType)
        enrolledModules[identifier] = moduleType
        return self
    }
    
    /// Specifies the workspace region to ensure CDP requests are routed to the correct regional endpoint.
    /// Default values for apiHost and cdnHost are determined by the region.
    /// However, if apiHost or cdnHost are manually specified, those values override region-based defaults.
    @discardableResult
    public func region(_ region: Region) -> SDKConfigBuilder {
        self.region = region
        return self
    }

    /// To help you get setup with the SDK or debug SDK, change the log level of logs you wish to
    /// view from the SDK.
    @discardableResult
    public func logLevel(_ logLevel: CioLogLevel) -> SDKConfigBuilder {
        self.logLevel = logLevel
        return self
    }

    @available(iOSApplicationExtension, unavailable)
    public func build() -> SdkConfig {
        // create `SdkConfig` from given configurations
        let sdkConfig = SdkConfig(
            cdpApiKey: cdpApiKey,
            region: region,
            logLevel: logLevel,
            moduleTypes: enrolledModules.values.map { $0 },
            extensionValues: extensionValues
        )

        return sdkConfig
    }
}
