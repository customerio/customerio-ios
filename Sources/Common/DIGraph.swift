import Foundation

public class DIGraph {
    public var overrides: [String: Any] = [:]
    public var singletons: [String: Any] = [:]

    public let siteId: SiteId
    internal init(siteId: String) {
        self.siteId = siteId
    }

    class Store {
        var instances: [String: DIGraph] = [:]
        func getInstance(siteId: String) -> DIGraph {
            if let existingInstance = instances[siteId] {
                return existingInstance
            }
            let newInstance = DIGraph(siteId: siteId)
            instances[siteId] = newInstance
            return newInstance
        }
    }

    @Atomic internal static var store = Store()
    public static func getInstance(siteId: String) -> DIGraph {
        Self.store.getInstance(siteId: siteId)
    }

    public static func getAllWorkspacesSharedInstance() -> DIGraph {
        Self.store.getInstance(siteId: "shared")
    }

    /**
     Designed to be used only in test classes to override dependencies.

     ```
     let mockOffRoadWheels = // make a mock of OffRoadWheels class
     DIGraph.shared.override(mockOffRoadWheels, OffRoadWheels.self)
     ```
     */
    public func override<Value: Any>(value: Value, forType type: Value.Type) {
        overrides[String(describing: type)] = value
    }

    /**
     Reset graph. Meant to be used in `tearDown()` of tests.
     */
    public func reset() {
        overrides = [:]
        singletons = [:]
    }
}
