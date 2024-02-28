import Foundation

/// Defines configuration options for the Customer.io SDK.
///
/// Use `SDKConfigBuilder` for constructing its instances. For detailed usage, see builder class documentation.
public struct SdkConfig {
    // Since `SdkConfig` is normally created outside of Common module, we provide a factory to create `SdkConfig` instances.
    public enum Factory {
        // Factory method to create `SdkConfig` with default values.
        public static func create(logLevel: CioLogLevel? = nil) -> SdkConfig {
            SdkConfig(logLevel: logLevel)
        }

        /// Constructs `SdkConfig` by parsing and applying configurations from provided dictionary.
        public static func create(from dictionary: [String: Any]) -> SdkConfig {
            // Build config using provided options.
            // Use each option from `dictionary` if present, otherwise use default value.
            // Ensure default values align with those in `SDKConfigBuilder`.
            // We'll later work on adding option to centralize default values in one place, ideally within this struct.

            var logLevel: CioLogLevel?
            if let logLevelStringValue = dictionary[Keys.logLevel.rawValue] as? String,
               let paramLogLevel = CioLogLevel.getLogLevel(for: logLevelStringValue) {
                logLevel = paramLogLevel
            }

            return SdkConfig(logLevel: logLevel)
        }
    }

    /// Constants used to map each of the options in SdkConfig.
    /// It's important to keep these values backwards compatible to avoid breaking SDK wrappers.
    public enum Keys: String {
        // config features
        case logLevel
    }

    public let logLevel: CioLogLevel

    // private init to ensure `SdkConfig` can be created using `SdkConfig.Factory` only.
    private init(logLevel: CioLogLevel?) {
        self.logLevel = logLevel ?? CioLogLevel.error
    }
}
