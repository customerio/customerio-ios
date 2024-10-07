import CioInternalCommon
import Foundation

/// Builder class designed to facilitate the creation of `MessagingInAppConfigOptions`.
/// The builder pattern allows for a fluent and intuitive way to set up configuration options for
/// the module, ensuring all required and optional settings are appropriately configured before the
/// module is initialized.
///
/// **Usage Example:**
///
/// ```
/// let config = MessagingInAppConfigBuilder(siteId, region: .US)
///   // additional configuration as needed...
///   .build()
/// // Use `config` for initializing in-app module...
/// ```
public class MessagingInAppConfigBuilder {
    // configuration options for MessagingInAppConfigOptions
    private let siteId: String
    private let region: Region

    /// Initializes new `MessagingInAppConfigBuilder` with required configuration options.
    /// - Parameters:
    ///   - siteId: Workspace Site ID
    ///   - region: Workspace Region
    public init(siteId: String, region: Region) {
        self.siteId = siteId
        self.region = region
    }

    /// Builds and returns `MessagingInAppConfigOptions` instance from the configured properties.
    public func build() -> MessagingInAppConfigOptions {
        MessagingInAppConfigOptions(
            siteId: siteId,
            region: region
        )
    }
}

/// Defines errors that can occur during the `MessagingInAppConfigBuilder` building process.
public enum MessagingInAppConfigBuilderError: Error {
    case malformedConfig
    case missingSiteId
    case invalidRegionType
}

public extension MessagingInAppConfigBuilder {
    /// Constants used to map each of the options in MessagingInAppConfigOptions.
    private enum Keys: String {
        case siteId
        case region
    }

    /// Constructs `MessagingInAppConfigOptions` by parsing and applying configurations from provided dictionary.
    /// The method is used to create `MessagingInAppConfigOptions` from wrapper SDK configurations.
    @available(iOSApplicationExtension, unavailable)
    static func build(from sdkConfig: [String: Any?]) throws -> MessagingInAppConfigOptions? {
        // If the inApp config is not present, then we assume the user does not want to use in-app messaging feature.
        guard let inAppConfig = sdkConfig["inApp"] else {
            return nil
        }
        // If the inApp config is present but it is not a dictionary, then we throw an error to indicate that the config is invalid.
        guard let config = inAppConfig as? [String: Any] else {
            throw MessagingInAppConfigBuilderError.malformedConfig
        }

        guard let siteId = config[Keys.siteId.rawValue] as? String else {
            throw MessagingInAppConfigBuilderError.missingSiteId
        }

        // By default, region is provided only in top-level configuration in wrapper SDKs.
        // This prevents users from having to specify region more than once in the configuration.
        // Therefore, we retrieve the region from top-level configuration here.
        // If the region is not present, the default region is used.
        let regionStr: String
        if let regionRawValue = sdkConfig[Keys.region.rawValue] {
            // This check ensures region is always provided as a string, and throwing an error can help
            // identify potential bugs when passing configuration values from wrappers.
            guard let rawValueAsString = regionRawValue as? String else {
                throw MessagingInAppConfigBuilderError.invalidRegionType
            }
            regionStr = rawValueAsString
        } else {
            regionStr = ""
        }
        let region = Region.getRegion(from: regionStr)

        return MessagingInAppConfigBuilder(siteId: siteId, region: region).build()
    }
}
