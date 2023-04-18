import Foundation

public class DIGraph {
    public let siteId: SiteId
    public let apiKey: String
    public let sdkConfig: SdkConfig

    public init(siteId: SiteId, apiKey: String, sdkConfig: SdkConfig) {
        self.siteId = siteId
        self.apiKey = apiKey
        self.sdkConfig = sdkConfig
    }

    public var overrides: [String: Any] = [:]
    public var singletons: [String: Any] = [:]

    /**
     Designed to be used only in test classes to override dependencies.

     ```
     let mockOffRoadWheels = // make a mock of OffRoadWheels class
     DIGraph.shared.override(mockOffRoadWheels, OffRoadWheels.self)
     ```
     */
    public func override<T: Any>(value: T, forType type: T.Type) {
        overrides[String(describing: type)] = value
    }

    // Retrieves an overridden instance of a specified type from the `overrides` dictionary.
    // If an overridden instance exists and can be cast to the specified type, it is returned; otherwise, nil is returned.
    public func getOverriddenInstance<T: Any>() -> T? {
        // Get the type name as the key for the dictionary.
        let typeName = String(describing: T.self)

        // Attempt to get and cast the overridden instance from the dictionary.
        if let overriddenInstance = overrides[typeName] as? T {
            return overriddenInstance
        }

        // If the instance is not found or cannot be cast, return nil.
        return nil
    }

    /**
     Reset graph. Meant to be used in `tearDown()` of tests.
     */
    public func reset() {
        overrides = [:]
        singletons = [:]
    }
}
