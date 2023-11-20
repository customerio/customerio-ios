import Foundation

public class ScopedDIGraph: DIServiceGraph {
    private let sdkConfig: SdkConfig
    private var scopedServices: [String: Any] = [:]

    public init(sdkConfig: SdkConfig) {
        self.sdkConfig = sdkConfig
        super.init()
    }

    // Add a scoped service
    public func addScopedService<T>(_ instance: T, forType type: T.Type) {
        scopedServices[String(describing: type)] = instance
    }

    // Retrieve a scoped service
    public func getScopedService<T>(ofType type: T.Type) -> T? {
        let typeName = String(describing: type)

        // Check for overrides first
        if let override = overrides[typeName] as? T {
            return override
        }

        // Retrieve a scoped service if no override is found
        return scopedServices[typeName] as? T
    }

    // Overrides the reset function to include scopedServices
    override public func reset() {
        super.reset()
        scopedServices = [:]
    }

    // Inherits the ability to use singletons and overrides from DIGraph
    // For example, using getSingleton(ofType:) to access singletons
}
