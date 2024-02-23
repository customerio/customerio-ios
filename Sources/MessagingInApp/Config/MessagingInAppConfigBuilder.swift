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
    public init(siteId: String, region: Region = .US) {
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
    case missingSiteId
}

public extension MessagingInAppConfigBuilder {
    /// Constants used to map each of the options in MessagingInAppConfigOptions.
    enum Keys: String {
        case siteId
        case region
    }

    /// Constructs `MessagingInAppConfigOptions` by parsing and applying configurations from provided dictionary.
    @available(iOSApplicationExtension, unavailable)
    static func build(from dictionary: [String: Any]) throws -> MessagingInAppConfigOptions {
        guard let siteId = dictionary[Keys.siteId.rawValue] as? String else {
            throw MessagingInAppConfigBuilderError.missingSiteId
        }

        if let region = (dictionary[Keys.region.rawValue] as? String).map(Region.getRegion) {
            return MessagingInAppConfigBuilder(siteId: siteId, region: region).build()
        } else {
            return MessagingInAppConfigBuilder(siteId: siteId).build()
        }
    }
}
