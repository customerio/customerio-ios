import Foundation

/// Protocol defining methods to load resource files, such as `plist` and `json`, from SDK's resource bundle.
protocol SdkResourceLoader: AutoMockable {
    /// Loads and returns a dictionary from `plist` file.
    ///
    /// - Returns: Dictionary containing contents of the `plist` file, or `nil` if the file could not be loaded.
    func loadPlist() -> [String: Any]?
    /// Loads and returns a dictionary from client info json file.
    ///
    /// - Returns: Dictionary containing parsed contents of the `json` file, or `nil` if the file could not be loaded.
    func loadClientInfoJson() -> [String: Any]?
}

// sourcery: InjectRegisterShared = "SdkResourceLoader"
// sourcery: InjectCustomShared
// sourcery: InjectSingleton
class CustomerIOResourceLoader: SdkResourceLoader {
    private let logger: Logger
    private let resourceBundle: Bundle?

    init(logger: Logger, bundle: Bundle?) {
        self.logger = logger
        self.resourceBundle = bundle
    }

    convenience init(logger: Logger) {
        let bundle: Bundle?
        // Wrapper SDKs should include resources in a separate bundle named "CustomerIO_Resources"
        // with required files like CIOClientInfo.json.
        let bundleName = "CustomerIO_Resources"
        // First, try to load the bundle associated with current class (common for SDKs or frameworks).
        // This checks if resource bundle is located within the same bundle as the class.
        if let bundleURL = Bundle(for: type(of: self)).url(forResource: bundleName, withExtension: "bundle") {
            bundle = Bundle(url: bundleURL)
        }
        // Fallback to main app bundle if the resource is not found in the framework or class bundle.
        // This is useful if the resource is part of the main app package rather than the framework.
        else if let bundleURL = Bundle.main.url(forResource: bundleName, withExtension: "bundle") {
            bundle = Bundle(url: bundleURL)
        }
        // If neither bundle contains the resource, set bundle to nil.
        else {
            bundle = nil
        }
        self.init(logger: logger, bundle: bundle)
    }

    func loadPlist() -> [String: Any]? {
        guard let bundle = resourceBundle else { return nil }
        guard let plistURL = bundle.url(forResource: "Info", withExtension: "plist") else {
            logger.error("Could not find Info.plist in \(String(describing: bundle.bundleIdentifier))")
            return nil
        }

        do {
            let data = try Data(contentsOf: plistURL)
            return try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        } catch {
            logger.error("Failed to read Info.plist: \(error)")
            return nil
        }
    }

    func loadClientInfoJson() -> [String: Any]? {
        guard let bundle = resourceBundle else { return nil }
        guard let jsonURL = bundle.url(forResource: "CIOClientInfo", withExtension: "json") else {
            logger.error("Could not find CIOClientInfo.json in \(String(describing: bundle.bundleIdentifier))")
            return nil
        }

        do {
            let data = try Data(contentsOf: jsonURL)
            return try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        } catch {
            logger.error("Failed to load or parse CIOClientInfo.json: \(error)")
            return nil
        }
    }
}

// Added extension as it provides default behavior and simplifies testing for SdkResourceLoader mocks.
extension SdkResourceLoader {
    /// Resolves and returns `SdkClient` by loading and combining data from `plist` and `json` resources.
    ///
    /// - Returns: `SdkClient` object if both `clientSource` and `clientVersion` can be resolved from resources, or `nil` if required data is missing.
    func resolveSdkClient() -> SdkClient? {
        let plistData = loadPlist()
        let clientInfoJson = loadClientInfoJson()

        // Return nil if both plistData and clientInfoJson are nil
        // This means that both resources are missing and we are likely in native iOS SDK
        guard plistData != nil || clientInfoJson != nil else {
            return nil
        }

        // Fetch values from json and plist files
        let clientSource = clientInfoJson?["clientSource"] as? String
        // Prefer clientVersion from clientInfoJson, fallback to Info.plist
        let clientVersion = clientInfoJson?["clientVersion"] as? String ?? plistData?["CFBundleShortVersionString"] as? String

        // Return SdkClient only if we have valid source and version
        if let source = clientSource, let version = clientVersion {
            return CustomerIOSdkClient(source: source, sdkVersion: version)
        }

        // Ideally, this should never be reached as we should always have valid source and version if resources were found.
        DIGraphShared.shared.logger.error("Failed to resolve SdkClient from resources. Source: \(String(describing: clientSource)), Version: \(String(describing: clientVersion))")
        return nil
    }
}

// Extension to provide custom SdkResourceLoader initialization in DIGraphShared.
extension DIGraphShared {
    var customSdkResourceLoader: SdkResourceLoader {
        CustomerIOResourceLoader(logger: logger)
    }
}
